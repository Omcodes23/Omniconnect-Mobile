/// AI chat state for the fully local, on-device runtime.
///
/// There is no provider to pick and no inference server to reach: this file
/// drives the embedded llama.cpp runtime through [LocalEngine], streams tokens
/// into [AiState.streamingReply], and persists conversations to disk with
/// [ConversationStore]. The only network traffic in the whole flow is the
/// one-time model download performed by [LocalModelManager], which goes straight
/// to the HuggingFace CDN over plain HTTPS — no auth, no API key, no OmniConnect
/// server involved.
///
/// The companion-mode toggle is the one part that needs OmniConnect Desktop: the
/// desktop backend is what registers the AI as a chat node, so this proxies the
/// toggle to `POST /api/ai/bot/toggle` and reports honestly when that backend is
/// unreachable.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'device_provider.dart';
import 'local_ai/ai_models.dart';
import 'local_ai/conversation_store.dart';
import 'local_ai/local_engine.dart';
import 'local_ai/model_catalog.dart';
import 'local_ai/model_manager.dart';

// The message + conversation types and the catalog used to live in this file.
// They are re-exported so every existing `import '.../services/ai_provider.dart';`
// keeps compiling with no changes at the call sites.
export 'local_ai/ai_models.dart';
export 'local_ai/model_catalog.dart' show ModelCatalog, ModelCatalogEntry;
export 'local_ai/model_manager.dart' show LocalModelStatus;

/// Sentinel used by [AiState.copyWith] so a nullable field can be *cleared*
/// rather than only replaced.
const Object _unset = Object();

/// Everything the AI screen renders.
class AiState {
  /// All saved chats, newest first.
  final List<AiConversation> conversations;

  /// The chat currently open, if any.
  final String? currentConversationId;

  /// Committed messages of [currentConversationId] (user + assistant).
  final List<AiMessage> currentMessages;

  /// The catalog with per-model download state, in catalog order.
  final List<LocalModelStatus> models;

  /// The selected model id (falls back to the catalog default).
  final String activeModelId;

  /// The model currently downloading, if any.
  final String? downloadingModelId;

  /// Progress (0..1) of [downloadingModelId].
  final double downloadProgress;

  /// A generation has been requested and the first token has not arrived yet
  /// (which includes the time spent loading a model into the runtime).
  final bool isLoading;

  /// Tokens are actively streaming.
  final bool isStreaming;

  /// The reply generated so far, or null when nothing is streaming.
  ///
  /// Kept separate from [currentMessages] so a partial reply is never written to
  /// disk; the authoritative full text is only committed once generation ends.
  final String? streamingReply;

  /// Companion mode (the AI appears as a chat node other people can message).
  final bool companionEnabled;

  /// `'online' | 'offline' | 'no-model' | 'loading' | 'unknown'`.
  ///
  /// The first three mirror the desktop backend. `'loading'` is this client's
  /// in-flight state and `'unknown'` means the backend could not be reached.
  final String companionStatus;

  /// The last user-facing error, if any.
  final String? error;

  /// False when the native runtime is not installed on this device.
  final bool runtimeAvailable;

  const AiState({
    this.conversations = const [],
    this.currentConversationId,
    this.currentMessages = const [],
    this.models = const [],
    String? activeModelId,
    this.downloadingModelId,
    this.downloadProgress = 0,
    this.isLoading = false,
    this.isStreaming = false,
    this.streamingReply,
    this.companionEnabled = false,
    this.companionStatus = 'unknown',
    this.error,
    this.runtimeAvailable = true,
  }) : activeModelId = activeModelId ?? _defaultModelId;

  static const String _defaultModelId = 'qwen2.5-1.5b-instruct-q4km';

  /// True while a reply is being produced (including the model-loading phase).
  bool get isGenerating => isLoading || isStreaming;

  /// The selected model's status, if the catalog is loaded.
  LocalModelStatus? get activeModel {
    for (final m in models) {
      if (m.entry.id == activeModelId) return m;
    }
    return null;
  }

  /// True when the selected model is fully downloaded and chat can be sent.
  bool get hasReadyModel => activeModel?.isDownloaded ?? false;

  AiState copyWith({
    List<AiConversation>? conversations,
    Object? currentConversationId = _unset,
    List<AiMessage>? currentMessages,
    List<LocalModelStatus>? models,
    String? activeModelId,
    Object? downloadingModelId = _unset,
    double? downloadProgress,
    bool? isLoading,
    bool? isStreaming,
    Object? streamingReply = _unset,
    bool? companionEnabled,
    String? companionStatus,
    Object? error = _unset,
    bool? runtimeAvailable,
  }) {
    return AiState(
      conversations: conversations ?? this.conversations,
      currentConversationId: identical(currentConversationId, _unset)
          ? this.currentConversationId
          : currentConversationId as String?,
      currentMessages: currentMessages ?? this.currentMessages,
      models: models ?? this.models,
      activeModelId: activeModelId ?? this.activeModelId,
      downloadingModelId: identical(downloadingModelId, _unset)
          ? this.downloadingModelId
          : downloadingModelId as String?,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingReply: identical(streamingReply, _unset)
          ? this.streamingReply
          : streamingReply as String?,
      companionEnabled: companionEnabled ?? this.companionEnabled,
      companionStatus: companionStatus ?? this.companionStatus,
      error: identical(error, _unset) ? this.error : error as String?,
      runtimeAvailable: runtimeAvailable ?? this.runtimeAvailable,
    );
  }
}

/// Drives [LocalEngine] + [LocalModelManager] + [ConversationStore] and exposes
/// the result as [AiState].
///
/// [build] must be synchronous, so it returns an empty state and kicks off
/// [_init] on a microtask; the UI fills in as soon as the disk state and the
/// runtime probe are ready. Everything is lazy: the native runtime is only
/// touched once the AI screen is actually opened.
class AiNotifier extends Notifier<AiState> {
  LocalModelManager? _modelManager;
  LocalEngine? _engine;
  ConversationStore? _store;

  bool _initialized = false;
  bool _disposed = false;
  bool _generating = false;

  @override
  AiState build() {
    ref.onDispose(() {
      _disposed = true;
      _modelManager?.removeListener(_onModelsChanged);
      _engine?.dispose();
      _modelManager?.dispose();
    });
    Future.microtask(_init);
    return const AiState();
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> _init() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    final models = _modelManager = LocalModelManager();
    final store = _store = ConversationStore();
    final engine = _engine = LocalEngine();
    models.addListener(_onModelsChanged);

    // Restore chats first so the screen is useful even if the model store is
    // slow to enumerate (or the runtime is missing entirely).
    try {
      await store.initialize();
      final convs = store.conversations;
      final currentId = store.currentConversationId ??
          (convs.isNotEmpty ? convs.first.id : null);
      final current = currentId == null ? null : store.findById(currentId);
      _update((s) => s.copyWith(
            conversations: convs,
            currentConversationId: currentId,
            currentMessages: current?.messages ?? const [],
          ));
    } catch (e) {
      _update((s) => s.copyWith(error: 'Could not load your chats: $e'));
    }

    try {
      await models.initialize();
      _update((s) => s.copyWith(
            models: models.statuses,
            activeModelId: models.activeModelId,
          ));
    } catch (e) {
      _update((s) => s.copyWith(error: 'Could not read local models: $e'));
    }

    // One isolate spawn, then cached for the life of the provider.
    final available = await engine.probeRuntime();
    _update((s) => s.copyWith(runtimeAvailable: available));

    await refreshCompanionStatus();
  }

  // ── Conversations ───────────────────────────────────────────────────────

  /// Reload the saved chats from disk. Safe to call repeatedly.
  Future<void> loadConversations() async {
    final store = _store;
    if (store == null) return;
    await store.initialize();
    final convs = store.conversations;
    final currentId =
        store.currentConversationId ?? (convs.isNotEmpty ? convs.first.id : null);
    final current = currentId == null ? null : store.findById(currentId);
    _update((s) => s.copyWith(
          conversations: convs,
          currentConversationId: currentId,
          currentMessages: current?.messages ?? const [],
          error: null,
        ));
  }

  Future<void> createConversation(String title) async {
    final trimmed = title.trim();
    final conv = AiConversation(
      id: _newId(),
      title: trimmed.isEmpty ? 'New chat' : trimmed,
      provider: 'local',
      modelName: _activeModelId(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _saveConversation(conv);
    _update((s) => s.copyWith(
          currentConversationId: conv.id,
          currentMessages: const [],
          streamingReply: null,
          error: null,
        ));
  }

  Future<void> selectConversation(String conversationId) async {
    final conv = _store?.findById(conversationId);
    _update((s) => s.copyWith(
          currentConversationId: conversationId,
          currentMessages: conv?.messages ?? const [],
          streamingReply: null,
          error: null,
        ));
    try {
      await _store?.setCurrentConversation(conversationId);
    } catch (_) {
      // Selection just will not survive a restart; not worth an error banner.
    }
  }

  void clearError() => _update((s) => s.copyWith(error: null));

  // ── Sending ─────────────────────────────────────────────────────────────

  Future<void> sendMessage(String content) async {
    final text = content.trim();
    if (text.isEmpty || _generating || _disposed) return;

    final manager = _modelManager;
    if (manager == null) return;

    var conversationId = state.currentConversationId;
    var messages = <AiMessage>[
      ...state.currentMessages,
      AiMessage(
        id: _newId(),
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ),
    ];

    if (conversationId == null) {
      conversationId = _newId();
      final conv = AiConversation(
        id: conversationId,
        title: _titleFrom(messages),
        provider: 'local',
        modelName: _activeModelId(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _update((s) => s.copyWith(
            currentConversationId: conversationId,
            conversations: _mergeConversation(conv),
          ));
    }

    // Write the user turn immediately: it must survive a crash mid-reply.
    final id = conversationId;
    await _persistMessages(id, messages);
    _update((s) => s.copyWith(
          currentMessages: messages,
          error: null,
          streamingReply: null,
        ));

    // ── Honest pre-flight failures (no model / no runtime) ────────────────
    if (!state.runtimeAvailable) {
      await _finishReply(id, messages, LocalEngine.missingRuntimeMessage);
      return;
    }
    if (!state.hasReadyModel) {
      await _finishReply(id, messages, _noModelMessage);
      return;
    }

    _generating = true;
    _update((s) => s.copyWith(isLoading: true, isStreaming: false));

    final engine = _engine!;
    engine.clearCancelled();

    try {
      await _ensureModelLoaded();

      final reply = await engine.chat(
        messages: [
          for (final m in messages) LocalChatMessage(m.role, m.content),
        ],
        maxTokens: 512,
        onToken: (textSoFar) {
          _update((s) => s.copyWith(
                isLoading: false,
                isStreaming: true,
                streamingReply: textSoFar,
              ));
        },
      );

      final partial = state.streamingReply ?? '';
      final finalText = reply.trim().isNotEmpty ? reply : partial;

      if (engine.wasCancelled && finalText.trim().isEmpty) {
        // Nothing was produced before the stop: say so instead of adding an
        // empty bubble.
        _update((s) => s.copyWith(streamingReply: null, error: 'Generation stopped.'));
      } else {
        await _finishReply(id, messages, finalText);
      }
    } on LocalRuntimeMissingException catch (e) {
      _update((s) => s.copyWith(runtimeAvailable: false));
      await _finishReply(id, messages, e.message);
    } catch (e) {
      _update((s) => s.copyWith(streamingReply: null, error: null));
      await _finishReply(
        id,
        messages,
        'The reply could not be generated on this device. $e',
      );
    } finally {
      engine.clearCancelled();
      _generating = false;
      _update((s) => s.copyWith(
            isLoading: false,
            isStreaming: false,
            streamingReply: null,
          ));
    }
  }

  /// Ask the running generation to stop. Safe to call from the UI isolate even
  /// while the engine isolate is blocked inside the native call.
  void cancelGeneration() => _engine?.cancel();

  // ── Models ──────────────────────────────────────────────────────────────

  /// Start (or resume) a model download. Progress arrives via state updates.
  Future<void> startDownload(String modelId) async {
    final manager = _modelManager;
    if (manager == null) return;
    _update((s) => s.copyWith(error: null));
    try {
      await manager.download(modelId);
    } catch (e) {
      _update((s) => s.copyWith(error: 'Could not start the download: $e'));
    }
  }

  void cancelDownload(String modelId) => _modelManager?.cancelDownload(modelId);

  /// Switch the active model. The resident model is unloaded so the next send
  /// loads the new one.
  Future<void> selectModel(String modelId) async {
    final manager = _modelManager;
    if (manager == null) return;
    if (!manager.isDownloaded(modelId)) return;

    if (!await manager.setActiveModel(modelId)) return;

    try {
      await _engine?.unload();
    } catch (_) {
      // A failed unload just means the swap happens on the next send.
    }
    _update((s) => s.copyWith(
          activeModelId: manager.activeModelId,
          models: manager.statuses,
          error: null,
        ));
  }

  /// Delete a downloaded model, unloading it first when it is the resident one
  /// (Windows and Android cannot delete a mapped file).
  Future<void> deleteModel(String modelId) async {
    final manager = _modelManager;
    if (manager == null) return;

    final entry = ModelCatalog.find(modelId);
    final engine = _engine;
    if (entry != null && engine != null && engine.loadedPath == manager.pathFor(entry)) {
      try {
        await engine.unload();
      } catch (_) {
        // The delete below is best-effort anyway.
      }
    }

    await manager.delete(modelId);
    _update((s) => s.copyWith(models: manager.statuses));
  }

  // ── Companion mode ──────────────────────────────────────────────────────

  /// Read the AI chat node's current state from the desktop backend.
  Future<void> refreshCompanionStatus() async {
    try {
      final api = ref.read(apiServiceProvider);
      final json = await api.getMap('/api/ai/bot/status');
      _applyCompanion(json);
    } catch (_) {
      // Backend not running / not reachable: say so rather than guessing.
      _update((s) => s.copyWith(companionStatus: 'unknown'));
    }
  }

  /// Enable or disable companion mode through the desktop backend.
  Future<void> setCompanionEnabled(bool enabled) async {
    _update((s) => s.copyWith(
          companionEnabled: enabled,
          companionStatus: 'loading',
          error: null,
        ));
    try {
      final api = ref.read(apiServiceProvider);
      final deviceId = await DeviceListNotifier.getPersistentDeviceId();
      final displayName =
          ref.read(authStateProvider).user?.displayName ?? 'Device';
      final json = await api.post('/api/ai/bot/toggle', {
        'enabled': enabled,
        'modelId': state.activeModelId,
        'deviceId': deviceId,
        'deviceName': 'Mobile ($displayName)',
      });
      _applyCompanion(json);
    } catch (_) {
      _update((s) => s.copyWith(
            companionEnabled: false,
            companionStatus: 'unknown',
          ));
    }
  }

  void _applyCompanion(Map<String, dynamic> json) {
    _update((s) => s.copyWith(
          companionEnabled: json['enabled'] == true,
          companionStatus: json['status']?.toString() ?? 'unknown',
        ));
  }

  // ── Internals ───────────────────────────────────────────────────────────

  static const String _noModelMessage =
      'No local model is ready yet. Pick a model above and wait for its '
      'download to finish, then send your message again.';

  /// Load the active model into the runtime when it is not already resident.
  Future<void> _ensureModelLoaded() async {
    final engine = _engine!;
    final manager = _modelManager!;

    final path =
        manager.getModelPath(state.activeModelId) ?? manager.getActiveModelPath();
    if (path == null) {
      throw StateError(_noModelMessage);
    }
    if (engine.isModelLoaded && engine.loadedPath == path) return;

    final entry = ModelCatalog.find(state.activeModelId);
    await engine.loadModel(
      path,
      nCtx: entry?.contextLength ?? 4096,
      nThreads: LocalEngine.defaultThreadCount(),
    );
  }

  /// Commit the authoritative reply text and clear the streaming preview.
  Future<void> _finishReply(
    String conversationId,
    List<AiMessage> baseMessages,
    String text,
  ) async {
    final all = <AiMessage>[
      ...baseMessages,
      AiMessage(
        id: _newId(),
        role: 'assistant',
        content: text,
        timestamp: DateTime.now(),
      ),
    ];
    await _persistMessages(conversationId, all);
    _update((s) => s.copyWith(
          currentMessages:
              conversationId == s.currentConversationId ? all : s.currentMessages,
          streamingReply: null,
        ));
  }

  /// Save [messages] as the body of [conversationId], updating the in-memory
  /// list first so the UI never depends on the write succeeding.
  Future<void> _persistMessages(
    String conversationId,
    List<AiMessage> messages,
  ) async {
    final existing =
        _store?.findById(conversationId) ?? _findInState(conversationId);
    final base = existing ??
        AiConversation(
          id: conversationId,
          title: _titleFrom(messages),
          provider: 'local',
          modelName: _activeModelId(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
    final updated = base.copyWith(
      messages: messages,
      modelName: _activeModelId(),
      updatedAt: DateTime.now(),
    );

    _update((s) => s.copyWith(conversations: _mergeConversation(updated)));

    try {
      await _store?.save(updated);
    } catch (e) {
      _update((s) => s.copyWith(error: 'Could not save this chat: $e'));
    }
  }

  Future<void> _saveConversation(AiConversation conv) async {
    _update((s) => s.copyWith(conversations: _mergeConversation(conv)));
    try {
      await _store?.save(conv);
    } catch (e) {
      _update((s) => s.copyWith(error: 'Could not save this chat: $e'));
    }
  }

  /// Put [conv] at the top of the list (newest first) and drop any older copy.
  List<AiConversation> _mergeConversation(AiConversation conv) {
    final merged = <AiConversation>[
      conv,
      ...state.conversations.where((c) => c.id != conv.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }

  AiConversation? _findInState(String id) {
    for (final c in state.conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _onModelsChanged() {
    final manager = _modelManager;
    if (manager == null || _disposed) return;

    final statuses = manager.statuses;
    String? downloadingId;
    double progress = 0;
    for (final status in statuses) {
      if (status.isDownloading) {
        downloadingId = status.entry.id;
        progress = status.downloadProgress;
        break;
      }
    }

    _update((s) => s.copyWith(
          models: statuses,
          activeModelId: manager.activeModelId,
          downloadingModelId: downloadingId,
          downloadProgress: progress,
        ));
  }

  String _activeModelId() => state.activeModelId;

  void _update(AiState Function(AiState current) change) {
    if (_disposed) return;
    state = change(state);
  }

  static int _idCounter = 0;

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  static String _titleFrom(List<AiMessage> messages) {
    AiMessage? first;
    for (final m in messages) {
      if (m.role == 'user') {
        first = m;
        break;
      }
    }
    first ??= messages.isNotEmpty ? messages.first : null;
    if (first == null) return 'New chat';

    final words = first.content.trim().split(RegExp(r'\s+'));
    final title = words.take(6).join(' ');
    if (title.isEmpty) return 'New chat';
    return words.length > 6 ? '$title…' : title;
  }
}

final aiProvider = NotifierProvider<AiNotifier, AiState>(AiNotifier.new);
