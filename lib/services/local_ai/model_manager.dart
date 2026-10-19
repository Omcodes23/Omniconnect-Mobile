/// On-device GGUF model file management.
///
/// This is the Dart port of the desktop backend's `ModelManager`. It owns the
/// model directory, tracks what is downloaded / downloading / failing, and
/// remembers which model is selected. It is the *only* part of the mobile AI
/// stack that touches the network, and it does so exactly once per model: a
/// plain HTTPS GET against the HuggingFace CDN (no auth, no API key, no
/// OmniConnect server involved).
///
/// It is a [ChangeNotifier] so the UI can show live download progress without
/// any polling timers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// Status of a single catalogued model on this device.
///
/// [status] is one of `'not-downloaded'`, `'downloading'`, `'downloaded'`,
/// `'error'` — the same strings the desktop backend returns so a status string
/// means the same thing on both platforms.
class LocalModelStatus {
  final ModelCatalogEntry entry;
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;

  /// `'not-downloaded' | 'downloading' | 'downloaded' | 'error'`
  final String status;
  final String? error;

  const LocalModelStatus({
    required this.entry,
    required this.isDownloaded,
    required this.isDownloading,
    required this.downloadProgress,
    required this.status,
    this.error,
  });
}

class _DownloadState {
  bool running = false;
  bool cancelRequested = false;
  int bytesReceived = 0;
  int totalBytes = 0;
  String? error;
}

class LocalModelManager extends ChangeNotifier {
  static const String _dirName = 'models';
  static const String _activeStateFile = 'active-model.json';

  Directory? _dir;
  final Map<String, _DownloadState> _downloads = {};
  String? _activeModelId;
  bool _initialized = false;

  /// Model files live under the app's support directory, which is private to
  /// the app on every platform (no storage permission required).
  Directory? get directory => _dir;

  bool get isInitialized => _initialized;

  /// The selected model id, falling back to the catalog default whenever the
  /// stored id is missing or no longer catalogued — mirrors `ModelManager.ActiveModelId`.
  String get activeModelId {
    final stored = _activeModelId;
    if (stored != null && stored.isNotEmpty && ModelCatalog.find(stored) != null) {
      return stored;
    }
    return ModelCatalog.defaultModel.id;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    _activeModelId = await _loadActiveFromDisk();
    _initialized = true;
    notifyListeners();
  }

  /// Absolute path a catalogued model's file would have (exists or not).
  String pathFor(ModelCatalogEntry entry) {
    final dir = _dir;
    if (dir == null) return entry.fileName;
    return '${dir.path}${Platform.pathSeparator}${entry.fileName}';
  }

  /// Path to the selected model if it is fully downloaded, otherwise null.
  String? getActiveModelPath() {
    final entry = ModelCatalog.find(activeModelId);
    if (entry == null) return null;
    return getModelPath(entry.id);
  }

  /// Path to a specific model if it is fully downloaded, otherwise null.
  String? getModelPath(String? modelId) {
    final entry = ModelCatalog.find(modelId);
    if (entry == null) return null;
    final path = pathFor(entry);
    return _isCompleteSync(path, entry) ? path : null;
  }

  bool isDownloaded(String modelId) => getModelPath(modelId) != null;

  Future<bool> setActiveModel(String modelId) async {
    if (ModelCatalog.find(modelId) == null) return false;
    _activeModelId = modelId;
    await _saveActiveToDisk(modelId);
    notifyListeners();
    return true;
  }

  /// The catalog with per-model download state, in catalog order.
  List<LocalModelStatus> get statuses {
    return ModelCatalog.all.map((entry) {
      final path = pathFor(entry);
      final complete = _isCompleteSync(path, entry);
      final state = _downloads[entry.id];

      if (state != null && state.running) {
        final total = state.totalBytes > 0 ? state.totalBytes : entry.sizeBytes;
        final progress =
            total > 0 ? (state.bytesReceived / total).clamp(0.0, 1.0) : 0.0;
        return LocalModelStatus(
          entry: entry,
          isDownloaded: complete,
          isDownloading: true,
          downloadProgress: progress,
          status: 'downloading',
        );
      }
      if (state != null && state.error != null && !complete) {
        return LocalModelStatus(
          entry: entry,
          isDownloaded: false,
          isDownloading: false,
          downloadProgress: 0,
          status: 'error',
          error: state.error,
        );
      }
      if (complete) {
        return LocalModelStatus(
          entry: entry,
          isDownloaded: true,
          isDownloading: false,
          downloadProgress: 1,
          status: 'downloaded',
        );
      }
      return LocalModelStatus(
        entry: entry,
        isDownloaded: false,
        isDownloading: false,
        downloadProgress: 0,
        status: 'not-downloaded',
      );
    }).toList(growable: false);
  }

  bool isDownloading(String modelId) => _downloads[modelId]?.running ?? false;

  double progressFor(String modelId) {
    final state = _downloads[modelId];
    if (state == null) return 0;
    final entry = ModelCatalog.find(modelId);
    final total = state.totalBytes > 0
        ? state.totalBytes
        : (entry?.sizeBytes ?? 0);
    if (total <= 0) return 0;
    return (state.bytesReceived / total).clamp(0.0, 1.0);
  }

  /// Start (or resume) a download. Idempotent while already running.
  Future<void> download(String modelId) async {
    final entry = ModelCatalog.find(modelId);
    if (entry == null) return;
    await initialize();

    final path = pathFor(entry);
    if (_isCompleteSync(path, entry)) {
      notifyListeners();
      return;
    }

    final state = _downloads.putIfAbsent(entry.id, _DownloadState.new);
    if (state.running) return;

    state.running = true;
    state.cancelRequested = false;
    state.error = null;
    state.bytesReceived = await _partialLength(entry);
    state.totalBytes = entry.sizeBytes;
    notifyListeners();

    // Deliberately not awaited: the caller gets progress via notifications.
    unawaited(_runDownload(entry, state));
  }

  /// Stop an in-flight download. The `.part` file is kept so it can resume.
  void cancelDownload(String modelId) {
    final state = _downloads[modelId];
    if (state != null && state.running) {
      state.cancelRequested = true;
    }
  }

  /// Delete a downloaded model (cancelling first when needed).
  Future<bool> delete(String modelId) async {
    final entry = ModelCatalog.find(modelId);
    if (entry == null) return false;

    final state = _downloads[entry.id];
    if (state != null) {
      state.cancelRequested = true;
      for (var i = 0; i < 40 && state.running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      _downloads.remove(entry.id);
    }

    var removed = false;
    for (final candidate in [pathFor(entry), '${pathFor(entry)}.part']) {
      try {
        final file = File(candidate);
        if (await file.exists()) {
          await file.delete();
          removed = true;
        }
      } catch (_) {
        // Best effort: a locked file is not fatal.
      }
    }
    if (removed) notifyListeners();
    return removed;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  Future<int> _partialLength(ModelCatalogEntry entry) async {
    try {
      final file = File('${pathFor(entry)}.part');
      return await file.exists() ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _runDownload(
      ModelCatalogEntry entry, _DownloadState state) async {
    final finalPath = pathFor(entry);
    final partPath = '$finalPath.part';
    final client = http.Client();

    try {
      var offset = await _partialLength(entry);

      final request = http.Request('GET', Uri.parse(entry.downloadUrl));
      request.headers['User-Agent'] = 'OmniConnect/1.0';
      if (offset > 0) {
        request.headers['Range'] = 'bytes=$offset-';
      }

      final response = await client.send(request);

      // If the server ignored our Range request, restart rather than corrupt
      // the file by appending a full body onto a partial one.
      if (offset > 0 && response.statusCode != 206) {
        offset = 0;
        await _tryDelete(partPath);
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException(
            'Download failed with HTTP ${response.statusCode}.',
            uri: Uri.parse(entry.downloadUrl));
      }

      final contentLength =
          response.contentLength ?? (entry.sizeBytes - offset);
      state.bytesReceived = offset;
      state.totalBytes = offset + contentLength > 0
          ? offset + contentLength
          : entry.sizeBytes;
      notifyListeners();

      final sink = File(partPath).openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.stream) {
          if (state.cancelRequested) {
            throw const _DownloadCancelled();
          }
          sink.add(chunk);
          state.bytesReceived += chunk.length;
          notifyListeners();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // Promote the .part file only once complete, so a half-written file is
      // never mistaken for a usable model.
      final finalFile = File(finalPath);
      if (await finalFile.exists()) await finalFile.delete();
      await File(partPath).rename(finalPath);

      if (!_isCompleteSync(finalPath, entry)) {
        throw const FileSystemException('Downloaded file failed verification.');
      }

      state.running = false;
      state.error = null;
      state.bytesReceived = state.totalBytes;
      notifyListeners();
    } on _DownloadCancelled {
      state.running = false;
      state.error = null;
      notifyListeners();
    } catch (e) {
      state.running = false;
      state.error = e.toString();
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// A model file is usable when it exists, is not obviously truncated, and
  /// starts with the GGUF magic bytes.
  ///
  /// Hashes are not published for every catalog entry, so verification relies
  /// on size + magic rather than a checksum — the same honest trade-off the
  /// desktop backend makes.
  bool _isCompleteSync(String path, ModelCatalogEntry entry) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      if (file.lengthSync() < (entry.sizeBytes * 0.95).floor()) return false;

      final raf = file.openSync();
      try {
        final magic = raf.readSync(4);
        return magic.length == 4 &&
            magic[0] == 0x47 && // G
            magic[1] == 0x47 && // G
            magic[2] == 0x55 && // U
            magic[3] == 0x46; //   F
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _tryDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort.
    }
  }

  File? get _activeStateFileRef {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$_activeStateFile');
  }

  Future<String?> _loadActiveFromDisk() async {
    try {
      final file = _activeStateFileRef;
      if (file == null || !await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded['modelId']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveActiveToDisk(String modelId) async {
    try {
      final file = _activeStateFileRef;
      if (file == null) return;
      await file.writeAsString(jsonEncode({'modelId': modelId}));
    } catch (_) {
      // Not fatal: the selection just will not survive a restart.
    }
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
