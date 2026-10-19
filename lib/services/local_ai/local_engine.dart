/// Runs the embedded llama.cpp runtime (`omni_llama`) off the UI thread.
///
/// llama.cpp is a synchronous, CPU-bound native call: running `oc_chat` on the
/// UI isolate would freeze the frame loop for the entire generation. So the
/// native library is driven from a dedicated *engine isolate* that owns the
/// loaded model, while the UI isolate talks to it over [SendPort]s.
///
/// Two details make streaming and cancellation work:
///
///  * **Streaming.** The token callback is a
///    [NativeCallable.isolateLocal] created *inside* the engine isolate. That
///    is valid — and cheap — because llama.cpp invokes the callback
///    synchronously on the thread that called `oc_chat`, which is the engine
///    isolate itself. The callback forwards raw byte chunks to whoever asked
///    for the generation. `SendPort.send` never blocks on the *sending*
///    isolate's event loop, so tokens flow even though that loop is currently
///    stuck inside `oc_chat`.
///
///  * **Cancellation.** A message cannot be delivered to the engine isolate
///    while it is blocked in `oc_chat`. Instead the UI isolate opens the same
///    shared library (the OS returns the same handle, so a
///    `Pointer<OcModel>` from the engine isolate is valid there) and calls
///    `oc_cancel` directly. The shim checks the flag once per token, so this
///    stops generation within one token.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'omni_llama_bindings.dart';

/// One message handed to the model. Synthetic messages (for example an
/// injected system prompt) are fine, which is why this is not [AiMessage].
class LocalChatMessage {
  final String role;
  final String content;

  const LocalChatMessage(this.role, this.content);
}

/// Thrown when the native `omni_llama` library is not present on this device.
class LocalRuntimeMissingException implements Exception {
  final String message;
  const LocalRuntimeMissingException(this.message);

  @override
  String toString() => message;
}

/// Handle to the engine isolate.
///
/// Create one per app, keep it alive, and call [dispose] only on shutdown: the
/// loaded model is expensive to build and is reused across requests.
class LocalEngine {
  static const String missingRuntimeMessage =
      'Local AI runtime not installed on this device. Build the native library '
      'with native/build-android.ps1 and rebuild the app.';

  Isolate? _isolate;
  ReceivePort? _fromEngine;
  SendPort? _toEngine;
  Future<void>? _startFuture;

  /// Opened on this isolate as well, purely so [cancel] can reach the shim
  /// while the engine isolate is blocked. Same underlying OS handle.
  OmniLlama? _lib;

  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _sequence = 0;

  bool _runtimeAvailable = true;
  int _modelAddress = 0;
  String? _loadedPath;
  int _contextSize = 0;
  bool _disposed = false;

  /// False when the shared library could not be opened on this device.
  bool get runtimeAvailable => _runtimeAvailable;

  /// True while a model is loaded and ready for [chat].
  bool get isModelLoaded => _modelAddress != 0;

  /// Path of the currently loaded model, if any.
  String? get loadedPath => _loadedPath;

  /// Context window (tokens) the model was loaded with.
  int get contextSize => _contextSize;

  /// Start the engine isolate (if it is not running yet) and report whether the
  /// native `omni_llama` library could actually be opened on this device.
  ///
  /// The check costs one isolate spawn the first time and nothing afterwards,
  /// and lets the UI distinguish "no runtime" from "no model" without
  /// attempting to load a multi-hundred-megabyte file.
  Future<bool> probeRuntime() async {
    await _ensureStarted();
    return _runtimeAvailable;
  }

  /// Suggested thread count: one per core, capped so small phones do not
  /// thrash. Matches the shim's own default ceiling.
  static int defaultThreadCount() {
    int cores;
    try {
      cores = Platform.numberOfProcessors;
    } catch (_) {
      cores = 4;
    }
    if (cores <= 0) return 4;
    return cores > 8 ? 8 : cores;
  }

  /// Load (or replace) the model served by the engine.
  ///
  /// Loading is synchronous inside the engine isolate and can take seconds for
  /// multi-gigabyte files, so await it before expecting [chat] to work.
  Future<void> loadModel(
    String path, {
    int nCtx = 4096,
    int? nThreads,
  }) async {
    await _ensureStarted();
    if (!_runtimeAvailable) {
      throw const LocalRuntimeMissingException(missingRuntimeMessage);
    }

    final response = await _request({
      'type': 'load',
      'path': path,
      'nCtx': nCtx,
      'nThreads': nThreads ?? defaultThreadCount(),
    });

    if (response['ok'] != true) {
      final message = response['error']?.toString() ??
          'The model could not be loaded.';
      if (response['code'] == 'no-runtime') {
        _runtimeAvailable = false;
        throw LocalRuntimeMissingException(message);
      }
      throw StateError(message);
    }

    _modelAddress = (response['addr'] as int?) ?? 0;
    _loadedPath = path;
    _contextSize = (response['nCtx'] as int?) ?? nCtx;
  }

  /// Run a chat completion and return the full reply text.
  ///
  /// When [onToken] is supplied it is called with the text generated *so far*
  /// after every token, which is what the UI renders. The returned string is
  /// authoritative: it is the shim's own output buffer, not a reassembly of the
  /// streamed chunks, so a dropped or malformed chunk can never corrupt the
  /// final message.
  Future<String> chat({
    required List<LocalChatMessage> messages,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    int seed = 0,
    void Function(String textSoFar)? onToken,
  }) async {
    await _ensureStarted();
    if (!_runtimeAvailable) {
      throw const LocalRuntimeMissingException(missingRuntimeMessage);
    }
    if (!isModelLoaded) {
      throw StateError('No local model is loaded.');
    }

    final id = ++_sequence;
    ReceivePort? tokenPort;
    StreamSubscription<dynamic>? tokenSub;

    if (onToken != null) {
      tokenPort = ReceivePort();
      final accumulator = <int>[];
      tokenSub = tokenPort.listen((event) {
        if (event is! Map) return;
        if (event['type'] != 'token' || event['id'] != id) return;
        final chunk = event['bytes'];
        if (chunk is Uint8List) {
          accumulator.addAll(chunk);
          // Decode leniently: a chunk boundary can fall in the middle of a
          // UTF-8 sequence, so the tail may be a replacement character for one
          // frame. The next frame fixes it.
          onToken(utf8.decode(accumulator, allowMalformed: true));
        }
      });
    }

    try {
      final response = await _request({
        'type': 'chat',
        'messages': [
          for (final m in messages) {'role': m.role, 'content': m.content},
        ],
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'seed': seed,
        if (tokenPort != null) 'streamPort': tokenPort.sendPort,
      }, id: id);

      if (response['ok'] != true) {
        throw StateError(
            response['error']?.toString() ?? 'Generation failed.');
      }
      return response['text']?.toString() ?? '';
    } finally {
      await tokenSub?.cancel();
      tokenPort?.close();
    }
  }

  /// True when the current generation was stopped with [cancel].
  bool _wasCancelled = false;
  bool get wasCancelled => _wasCancelled;

  /// Ask the running generation to stop. Safe to call from any isolate: it does
  /// not go through the (blocked) engine message queue.
  void cancel() {
    final lib = _lib;
    final address = _modelAddress;
    if (lib == null || address == 0) return;
    _wasCancelled = true;
    lib.cancel(Pointer<OcModel>.fromAddress(address), 1);
  }

  void clearCancelled() => _wasCancelled = false;

  /// Compute an embedding vector for [text] (the model's pooled, mean vector).
  Future<List<double>> embed(String text) async {
    await _ensureStarted();
    if (!_runtimeAvailable) {
      throw const LocalRuntimeMissingException(missingRuntimeMessage);
    }
    if (!isModelLoaded) {
      throw StateError('No local model is loaded.');
    }

    final response = await _request({'type': 'embed', 'text': text});
    if (response['ok'] != true) {
      throw StateError(
          response['error']?.toString() ?? 'Embedding failed.');
    }
    final vector = response['vector'];
    if (vector is List) {
      return vector.map((v) => (v as num).toDouble()).toList(growable: false);
    }
    return const <double>[];
  }

  /// Release the loaded model, keeping the engine isolate alive.
  Future<void> unload() async {
    if (_toEngine == null) {
      _modelAddress = 0;
      _loadedPath = null;
      _contextSize = 0;
      return;
    }
    try {
      await _request({'type': 'unload'});
    } finally {
      _modelAddress = 0;
      _loadedPath = null;
      _contextSize = 0;
    }
  }

  /// Shut the engine isolate down for good.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('The local AI engine was shut down.'));
      }
    }
    _pending.clear();

    _toEngine?.send({'type': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    _fromEngine?.close();
    _isolate = null;
    _toEngine = null;
    _modelAddress = 0;
    _loadedPath = null;
    _contextSize = 0;
  }

  // ── Plumbing ────────────────────────────────────────────────────────────

  Future<void> _ensureStarted() {
    final existing = _startFuture;
    if (existing != null) return existing;
    final future = _start();
    _startFuture = future;
    return future;
  }

  Future<void> _start() async {
    final fromEngine = ReceivePort();
    _fromEngine = fromEngine;
    final ready = Completer<void>();

    fromEngine.listen((dynamic event) {
      if (event is! Map) return;
      final message = Map<String, dynamic>.from(event);

      switch (message['type']) {
        case 'ready':
          _toEngine = message['port'] as SendPort?;
          _runtimeAvailable = message['runtime'] == true;
          // Second view of the same shared library, used only by cancel().
          _lib = _runtimeAvailable ? OmniLlama.tryOpen() : null;
          if (!ready.isCompleted) ready.complete();
          return;
        case 'token':
          // Delivered straight to the per-request token port instead.
          return;
      }

      final id = message['id'];
      if (id is int) {
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
      }
    });

    _isolate = await Isolate.spawn<SendPort>(
      _engineIsolateMain,
      fromEngine.sendPort,
      debugName: 'omni-llama-engine',
      errorsAreFatal: false,
    );

    await ready.future;
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> message, {
    int? id,
  }) async {
    await _ensureStarted();
    final toEngine = _toEngine;
    if (toEngine == null) {
      throw StateError('The local AI engine is not running.');
    }

    final requestId = id ?? ++_sequence;
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    toEngine.send({...message, 'id': requestId});
    return completer.future;
  }
}

// ── Engine isolate ──────────────────────────────────────────────────────────

/// Entry point for the engine isolate. Never returns, so the isolate lives for
/// as long as the app does.
Future<void> _engineIsolateMain(SendPort toMain) {
  final receive = ReceivePort();
  final runtime = _EngineRuntime(toMain);
  runtime.bind(receive);
  runtime.announce();
  return Completer<void>().future;
}

class _EngineRuntime {
  final SendPort _toMain;
  ReceivePort? _receive;
  OmniLlama? _lib;
  Pointer<OcModel> _model = nullptr;

  _EngineRuntime(this._toMain);

  bool get _runtimeAvailable => _lib != null;

  void bind(ReceivePort receive) {
    _receive = receive;
    _lib = OmniLlama.tryOpen();
    receive.listen(_onMessage);
  }

  void announce() {
    _toMain.send({
      'type': 'ready',
      'port': _receive?.sendPort,
      'runtime': _runtimeAvailable,
    });
  }

  void _onMessage(dynamic raw) {
    if (raw is! Map) return;
    final message = Map<String, dynamic>.from(raw);
    switch (message['type']) {
      case 'load':
        _load(message);
      case 'chat':
        _chat(message);
      case 'embed':
        _embed(message);
      case 'unload':
        _unload(message);
      case 'dispose':
        _dispose();
    }
  }

  void _reply(Map<String, dynamic> message) => _toMain.send(message);

  // ── load ────────────────────────────────────────────────────────────────

  void _load(Map<String, dynamic> message) {
    final id = message['id'];
    _freeModel();

    final lib = _lib;
    if (lib == null) {
      _reply({
        'type': 'loadResult',
        'id': id,
        'ok': false,
        'code': 'no-runtime',
        'error': LocalEngine.missingRuntimeMessage,
      });
      return;
    }

    final path = message['path'] as String?;
    if (path == null || path.isEmpty) {
      _reply({
        'type': 'loadResult',
        'id': id,
        'ok': false,
        'code': 'bad-request',
        'error': 'No model path was supplied.',
      });
      return;
    }

    final nCtx = (message['nCtx'] as int?) ?? 4096;
    final nThreads = (message['nThreads'] as int?) ?? 0;

    final pathPtr = path.toNativeUtf8();
    const errLen = 1024;
    final errPtr = calloc<Uint8>(errLen);
    try {
      final loaded = lib.load(pathPtr, nCtx, nThreads, errPtr, errLen);
      if (loaded == nullptr) {
        final reason = _readCString(errPtr, errLen);
        _reply({
          'type': 'loadResult',
          'id': id,
          'ok': false,
          'code': 'load-failed',
          'error': reason.isEmpty ? 'The model could not be loaded.' : reason,
        });
        return;
      }

      _model = loaded;
      _reply({
        'type': 'loadResult',
        'id': id,
        'ok': true,
        'addr': loaded.address,
        'nCtx': lib.contextSize(loaded),
      });
    } catch (e) {
      _reply({
        'type': 'loadResult',
        'id': id,
        'ok': false,
        'code': 'load-failed',
        'error': e.toString(),
      });
    } finally {
      calloc.free(pathPtr);
      calloc.free(errPtr);
    }
  }

  // ── chat ────────────────────────────────────────────────────────────────

  void _chat(Map<String, dynamic> message) {
    final id = message['id'];
    final lib = _lib;
    final model = _model;

    if (lib == null) {
      _reply({
        'type': 'chatResult',
        'id': id,
        'ok': false,
        'code': 'no-runtime',
        'error': LocalEngine.missingRuntimeMessage,
      });
      return;
    }
    if (model == nullptr) {
      _reply({
        'type': 'chatResult',
        'id': id,
        'ok': false,
        'code': 'no-model',
        'error': 'No local model is loaded.',
      });
      return;
    }

    final rawMessages = (message['messages'] as List<dynamic>?) ?? const [];
    if (rawMessages.isEmpty) {
      _reply({
        'type': 'chatResult',
        'id': id,
        'ok': false,
        'code': 'bad-request',
        'error': 'The message list was empty.',
      });
      return;
    }

    final count = rawMessages.length;
    final streamPort = message['streamPort'] as SendPort?;
    final maxTokens = (message['maxTokens'] as int?) ?? 512;

    final messagesPtr = calloc<OcMessageStruct>(count);
    final allocated = <Pointer<Utf8>>[];
    NativeCallable<OcTokenCbNative>? callback;
    Pointer<Uint8>? outPtr;

    try {
      for (var i = 0; i < count; i++) {
        final entry = Map<String, dynamic>.from(rawMessages[i] as Map);
        final rolePtr = (entry['role'] as String? ?? 'user').toNativeUtf8();
        final contentPtr = (entry['content'] as String? ?? '').toNativeUtf8();
        allocated
          ..add(rolePtr)
          ..add(contentPtr);
        messagesPtr[i].role = rolePtr;
        messagesPtr[i].content = contentPtr;
      }

      if (streamPort != null) {
        // isolateLocal: llama.cpp calls this synchronously on the thread that
        // invoked oc_chat — this isolate — so no message round-trip is needed.
        callback = NativeCallable<OcTokenCbNative>.isolateLocal(
          (Pointer<Uint8> piece, int pieceLen, Pointer<Void> userData) {
            if (pieceLen <= 0) return;
            // The pointer is only valid for the duration of this call, so take
            // a copy before handing it to another isolate.
            streamPort.send({
              'type': 'token',
              'id': id,
              'bytes': Uint8List.fromList(piece.asTypedList(pieceLen)),
            });
          },
        );
      }

      // Generous ceiling: ~64 bytes per token covers every script we ship, and
      // the shim's byte count is authoritative for what was actually written.
      final wanted = maxTokens * 64 + 4096;
      final outLen = wanted < 16384
          ? 16384
          : (wanted > 8388608 ? 8388608 : wanted);
      outPtr = calloc<Uint8>(outLen);

      final written = lib.chat(
        model,
        messagesPtr,
        count,
        maxTokens,
        (message['temperature'] as num?)?.toDouble() ?? 0.7,
        (message['topP'] as num?)?.toDouble() ?? 0.9,
        (message['topK'] as int?) ?? 40,
        (message['seed'] as int?) ?? 0,
        outPtr,
        outLen,
        callback?.nativeFunction ?? nullptr,
        nullptr,
      );

      if (written < 0) {
        _reply({
          'type': 'chatResult',
          'id': id,
          'ok': false,
          'code': 'chat-failed',
          'error': 'Generation failed (code $written).',
        });
        return;
      }

      final text = utf8.decode(
        outPtr.asTypedList(written),
        allowMalformed: true,
      );
      _reply({
        'type': 'chatResult',
        'id': id,
        'ok': true,
        'text': text,
        'bytes': written,
      });
    } catch (e) {
      _reply({
        'type': 'chatResult',
        'id': id,
        'ok': false,
        'code': 'chat-failed',
        'error': e.toString(),
      });
    } finally {
      // Must outlive oc_chat, so it is only closed here.
      callback?.close();
      for (final pointer in allocated) {
        calloc.free(pointer);
      }
      calloc.free(messagesPtr);
      if (outPtr != null) calloc.free(outPtr);
    }
  }

  // ── embed ───────────────────────────────────────────────────────────────

  void _embed(Map<String, dynamic> message) {
    final id = message['id'];
    final lib = _lib;
    final model = _model;

    if (lib == null || model == nullptr) {
      _reply({
        'type': 'embedResult',
        'id': id,
        'ok': false,
        'code': lib == null ? 'no-runtime' : 'no-model',
        'error': lib == null
            ? LocalEngine.missingRuntimeMessage
            : 'No local model is loaded.',
      });
      return;
    }

    final textPtr = (message['text'] as String? ?? '').toNativeUtf8();
    Pointer<Float>? outPtr;
    try {
      final dim = lib.embedDim(model);
      if (dim <= 0) {
        _reply({
          'type': 'embedResult',
          'id': id,
          'ok': false,
          'code': 'embed-failed',
          'error': 'The model did not report an embedding size.',
        });
        return;
      }

      outPtr = calloc<Float>(dim);
      final written = lib.embed(model, textPtr, outPtr, dim);
      if (written < 0) {
        _reply({
          'type': 'embedResult',
          'id': id,
          'ok': false,
          'code': 'embed-failed',
          'error': 'Embedding failed (code $written).',
        });
        return;
      }

      _reply({
        'type': 'embedResult',
        'id': id,
        'ok': true,
        'vector': outPtr.asTypedList(dim).toList(growable: false),
      });
    } catch (e) {
      _reply({
        'type': 'embedResult',
        'id': id,
        'ok': false,
        'code': 'embed-failed',
        'error': e.toString(),
      });
    } finally {
      calloc.free(textPtr);
      if (outPtr != null) calloc.free(outPtr);
    }
  }

  // ── lifecycle ───────────────────────────────────────────────────────────

  void _unload(Map<String, dynamic> message) {
    final id = message['id'];
    _freeModel();
    _reply({'type': 'unloadResult', 'id': id, 'ok': true});
  }

  void _dispose() {
    _freeModel();
    _receive?.close();
    _receive = null;
    _lib = null;
    Isolate.current.kill(priority: Isolate.immediate);
  }

  void _freeModel() {
    final lib = _lib;
    final model = _model;
    if (lib != null && model != nullptr) {
      try {
        lib.free(model);
      } catch (_) {
        // Nothing useful to do: the isolate is going away or the model was
        // already released.
      }
    }
    _model = nullptr;
  }

  /// Reads a NUL-terminated UTF-8 string out of a fixed-size error buffer.
  String _readCString(Pointer<Uint8> pointer, int maxLength) {
    final bytes = <int>[];
    for (var i = 0; i < maxLength; i++) {
      final byte = pointer[i];
      if (byte == 0) break;
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
