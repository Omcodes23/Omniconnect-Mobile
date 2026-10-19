/// dart:ffi bindings for the OmniConnect llama.cpp shim (`omni_llama`).
///
/// The shim's C ABI is defined in
/// `Desktop-Application/native/omni_llama/omni_llama.h` and is deliberately
/// tiny: load / free / context_size / chat / embed / embed_dim / cancel, over
/// plain pointers and C strings. Nothing here knows anything about llama.cpp
/// structs, so an upstream bump of the vendored llama.cpp does not break these
/// bindings.
///
/// The same shared library is used by the desktop backend (C# P/Invoke). On
/// Android the file is `libomni_llama.so`, built from the canonical shim
/// sources by `android/app/build.gradle.kts` (externalNativeBuild.cmake).
library;

import 'dart:ffi';
import 'dart:io';

// `Utf8`, `calloc` and the `toNativeUtf8()` / `toDartString()` helpers live in
// package:ffi; dart:ffi itself only defines `Char`/`Opaque`.
import 'package:ffi/ffi.dart';

/// Opaque handle to a loaded model (mirrors `oc_model*`).
final class OcModel extends Opaque {}

/// Mirrors the C `oc_message` struct: two NUL-terminated UTF-8 pointers.
final class OcMessageStruct extends Struct {
  external Pointer<Utf8> role;
  external Pointer<Utf8> content;
}

/// `void oc_token_cb(const char* piece, int piece_len, void* user_data)`
///
/// `piece` is raw UTF-8 bytes for one token. It is NOT NUL-terminated as a
/// complete string and may split a multi-byte sequence: append the bytes and
/// decode once at the end. The return value is ignored by the shim; stop
/// generation with [OmniLlama.cancel] instead.
typedef OcTokenCbNative = Void Function(
    Pointer<Uint8> piece, Int32 pieceLen, Pointer<Void> userData);
typedef OcTokenCbDart = void Function(
    Pointer<Uint8> piece, int pieceLen, Pointer<Void> userData);

// ── oc_load ────────────────────────────────────────────────────────────
typedef OcLoadNative = Pointer<OcModel> Function(
    Pointer<Utf8> ggufPath, Int32 nCtx, Int32 nThreads, Pointer<Uint8> err, Int32 errLen);
typedef OcLoadDart = Pointer<OcModel> Function(
    Pointer<Utf8> ggufPath, int nCtx, int nThreads, Pointer<Uint8> err, int errLen);

// ── oc_free ────────────────────────────────────────────────────────────
typedef OcFreeNative = Void Function(Pointer<OcModel> m);
typedef OcFreeDart = void Function(Pointer<OcModel> m);

// ── oc_context_size ────────────────────────────────────────────────────
typedef OcContextSizeNative = Int32 Function(Pointer<OcModel> m);
typedef OcContextSizeDart = int Function(Pointer<OcModel> m);

// ── oc_chat ────────────────────────────────────────────────────────────
typedef OcChatNative = Int32 Function(
    Pointer<OcModel> m,
    Pointer<OcMessageStruct> messages,
    Int32 nMessages,
    Int32 maxTokens,
    Float temperature,
    Float topP,
    Int32 topK,
    Uint32 seed,
    Pointer<Uint8> out,
    Int32 outLen,
    Pointer<NativeFunction<OcTokenCbNative>> cb,
    Pointer<Void> userData);
typedef OcChatDart = int Function(
    Pointer<OcModel> m,
    Pointer<OcMessageStruct> messages,
    int nMessages,
    int maxTokens,
    double temperature,
    double topP,
    int topK,
    int seed,
    Pointer<Uint8> out,
    int outLen,
    Pointer<NativeFunction<OcTokenCbNative>> cb,
    Pointer<Void> userData);

// ── oc_embed ───────────────────────────────────────────────────────────
typedef OcEmbedNative = Int32 Function(
    Pointer<OcModel> m, Pointer<Utf8> text, Pointer<Float> out, Int32 outDim);
typedef OcEmbedDart = int Function(
    Pointer<OcModel> m, Pointer<Utf8> text, Pointer<Float> out, int outDim);

// ── oc_embed_dim ───────────────────────────────────────────────────────
typedef OcEmbedDimNative = Int32 Function(Pointer<OcModel> m);
typedef OcEmbedDimDart = int Function(Pointer<OcModel> m);

// ── oc_cancel ──────────────────────────────────────────────────────────
typedef OcCancelNative = Void Function(Pointer<OcModel> m, Int32 cancel);
typedef OcCancelDart = void Function(Pointer<OcModel> m, int cancel);

/// A loaded view of the `omni_llama` shared library.
///
/// Opening the library twice in the same process (e.g. once on the UI isolate
/// and once on the engine isolate) is fine and cheap: `DynamicLibrary.open`
/// returns the same underlying handle, so a `Pointer<OcModel>` obtained on one
/// isolate is valid on the other. That is what lets the UI isolate request a
/// cancellation for a generation currently running on the engine isolate.
class OmniLlama {
  final DynamicLibrary _lib;

  OmniLlama._(this._lib);

  late final OcLoadDart load =
      _lib.lookupFunction<OcLoadNative, OcLoadDart>('oc_load');
  late final OcFreeDart free =
      _lib.lookupFunction<OcFreeNative, OcFreeDart>('oc_free');
  late final OcContextSizeDart contextSize =
      _lib.lookupFunction<OcContextSizeNative, OcContextSizeDart>('oc_context_size');
  late final OcChatDart chat =
      _lib.lookupFunction<OcChatNative, OcChatDart>('oc_chat');
  late final OcEmbedDart embed =
      _lib.lookupFunction<OcEmbedNative, OcEmbedDart>('oc_embed');
  late final OcEmbedDimDart embedDim =
      _lib.lookupFunction<OcEmbedDimNative, OcEmbedDimDart>('oc_embed_dim');
  late final OcCancelDart cancel =
      _lib.lookupFunction<OcCancelNative, OcCancelDart>('oc_cancel');

  /// Candidate file names, in the order they are tried.
  static List<String> get candidateNames {
    if (Platform.isAndroid || Platform.isLinux) {
      return const ['libomni_llama.so', 'omni_llama.so'];
    }
    if (Platform.isWindows) {
      return const ['omni_llama.dll', 'libomni_llama.dll'];
    }
    if (Platform.isMacOS) {
      return const ['libomni_llama.dylib', 'omni_llama.dylib'];
    }
    if (Platform.isIOS) {
      return const ['libomni_llama.dylib'];
    }
    return const ['libomni_llama.so'];
  }

  /// Opens the library, or returns `null` when it is not present (for example a
  /// desktop build where `native/build-windows.ps1` has not been run yet).
  static OmniLlama? tryOpen() {
    for (final name in candidateNames) {
      try {
        return OmniLlama._(DynamicLibrary.open(name));
      } catch (_) {
        // Try the next candidate.
      }
    }
    return null;
  }

  /// Opens the library, throwing a clear message when it cannot be found.
  static OmniLlama open() {
    final lib = tryOpen();
    if (lib != null) return lib;
    throw StateError(
      'Local AI runtime not installed: could not load '
      '${candidateNames.first}. Build it with '
      'native/build-android.ps1 (mobile) or native/build-windows.ps1 (desktop).',
    );
  }
}
