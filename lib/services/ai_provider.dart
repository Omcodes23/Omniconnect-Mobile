import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class AiMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;

  AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        role: json['role'] ?? 'user',
        content: json['content'] ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
            : DateTime.now(),
      );
}

class AiConversation {
  final String id;
  final String title;
  final String provider;
  final String modelName;
  final List<AiMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiConversation({
    required this.id,
    required this.title,
    this.provider = 'OpenAI',
    this.modelName = 'gpt-4o',
    this.messages = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
        id: json['id']?.toString() ?? '',
        title: json['title'] ?? 'Untitled',
        provider: json['provider'] ?? 'OpenAI',
        modelName: json['modelName'] ?? 'gpt-4o',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
      );
}

class AiState {
  final List<AiConversation> conversations;
  final String? currentConversationId;
  final String selectedProvider;
  final String selectedModel;
  final bool isLoading;
  final String? error;
  final List<AiMessage> currentMessages;

  const AiState({
    this.conversations = const [],
    this.currentConversationId,
    this.selectedProvider = 'OpenAI',
    this.selectedModel = 'gpt-4o',
    this.isLoading = false,
    this.error,
    this.currentMessages = const [],
  });

  AiState copyWith({
    List<AiConversation>? conversations,
    String? currentConversationId,
    String? selectedProvider,
    String? selectedModel,
    bool? isLoading,
    String? error,
    List<AiMessage>? currentMessages,
  }) {
    return AiState(
      conversations: conversations ?? this.conversations,
      currentConversationId: currentConversationId ?? this.currentConversationId,
      selectedProvider: selectedProvider ?? this.selectedProvider,
      selectedModel: selectedModel ?? this.selectedModel,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentMessages: currentMessages ?? this.currentMessages,
    );
  }
}

class AiNotifier extends Notifier<AiState> {
  @override
  AiState build() => const AiState();

  void selectProvider(String provider) {
    final model = _defaultModel(provider);
    state = state.copyWith(selectedProvider: provider, selectedModel: model);
  }

  void selectModel(String model) {
    state = state.copyWith(selectedModel: model);
  }

  String _defaultModel(String provider) {
    switch (provider) {
      case 'Gemini':
        return 'gemini-2.0-flash';
      case 'Local':
        return 'llama-3.1-8b';
      default:
        return 'gpt-4o';
    }
  }

  /// Load conversations from the API
  Future<void> loadConversations() async {
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.getMap('/api/ai/conversations');
      final conversationsList = response['conversations'] as List<dynamic>? ?? [];
      final conversations = conversationsList
          .map((c) => AiConversation.fromJson(c as Map<String, dynamic>))
          .toList();
      state = state.copyWith(conversations: conversations);
    } catch (e) {
      // Silently fail — conversations list remains empty
    }
  }

  Future<void> createConversation(String title) async {
    // POST to /api/ai/chat with no conversationId to create a new conversation
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post('/api/ai/chat', {
        'provider': state.selectedProvider,
        'model': state.selectedModel,
        'message': 'Hello',
        'conversationId': null,
        'history': [],
      });

      final conversationId = response['conversationId']?.toString();
      final conv = AiConversation(
        id: conversationId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        provider: state.selectedProvider,
        modelName: state.selectedModel,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
        currentConversationId: conv.id,
        currentMessages: [],
      );
    } catch (e) {
      // Fallback: create locally if API fails
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final conv = AiConversation(
        id: id,
        title: title,
        provider: state.selectedProvider,
        modelName: state.selectedModel,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(
        conversations: [conv, ...state.conversations],
        currentConversationId: id,
        currentMessages: [],
      );
    }
  }

  void selectConversation(String id) {
    final conv = state.conversations.firstWhere(
      (c) => c.id == id,
      orElse: () => AiConversation(
        id: '',
        title: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    state = state.copyWith(
      currentConversationId: id,
      currentMessages: conv.messages,
    );
    // Load messages from API for this conversation
    _loadConversationMessages(id);
  }

  Future<void> _loadConversationMessages(String conversationId) async {
    state = state.copyWith(isLoading: true);
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.getMap('/api/ai/conversations/$conversationId');

      final messagesList = response['messages'] as List<dynamic>? ?? [];
      final messages = messagesList
          .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
          .toList();

      // Update conversation title if available
      final convData = response['conversation'] as Map<String, dynamic>?;
      final title = convData?['title'] as String?;

      final updatedConversations = state.conversations.map((c) {
        if (c.id == conversationId) {
          return AiConversation(
            id: c.id,
            title: title ?? c.title,
            provider: c.provider,
            modelName: c.modelName,
            messages: messages,
            createdAt: c.createdAt,
            updatedAt: DateTime.now(),
          );
        }
        return c;
      }).toList();

      state = state.copyWith(
        currentMessages: messages,
        isLoading: false,
        conversations: updatedConversations,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load messages: $e',
      );
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final userMsg = AiMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      currentMessages: [...state.currentMessages, userMsg],
      isLoading: true,
      error: null,
    );

    try {
      final api = ref.read(apiServiceProvider);

      // Build history from the last 20 messages (excluding the one we just added)
      final history = state.currentMessages
          .take(state.currentMessages.length - 1)
          .toList()
          .reversed
          .take(20)
          .map((m) => m.toJson())
          .toList();

      final response = await api.post('/api/ai/chat', {
        'provider': state.selectedProvider,
        'model': state.selectedModel,
        'message': content,
        'conversationId': state.currentConversationId,
        'history': history,
      });

      // Backend returns AiChatResponse with 'reply' field
      final replyContent = response['reply'] as String? ?? 'No response';
      final conversationId = response['conversationId']?.toString();

      final aiMsg = AiMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'assistant',
        content: replyContent,
        timestamp: DateTime.now(),
      );

      List<AiMessage> updatedMessages = [...state.currentMessages, aiMsg];

      // Update conversation in the list with new messages
      List<AiConversation> updatedConversations = List.from(state.conversations);
      if (conversationId != null) {
        final existingIndex = updatedConversations.indexWhere(
            (c) => c.id == conversationId);
        if (existingIndex >= 0) {
          updatedConversations[existingIndex] = AiConversation(
            id: conversationId,
            title: updatedConversations[existingIndex].title,
            provider: state.selectedProvider,
            modelName: state.selectedModel,
            messages: updatedMessages,
            createdAt: updatedConversations[existingIndex].createdAt,
            updatedAt: DateTime.now(),
          );
        } else {
          // New conversation created on server
          final title =
              content.length > 50 ? '${content.substring(0, 50)}...' : content;
          updatedConversations.insert(
            0,
            AiConversation(
              id: conversationId,
              title: title,
              provider: state.selectedProvider,
              modelName: state.selectedModel,
              messages: updatedMessages,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
      }

      state = state.copyWith(
        currentMessages: updatedMessages,
        isLoading: false,
        currentConversationId: conversationId ?? state.currentConversationId,
        conversations: updatedConversations,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to get AI response: $e',
        currentMessages: [
          ...state.currentMessages,
          AiMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            role: 'assistant',
            content: '**Error:** $e\n\nMake sure the backend is running and AI provider keys are configured.',
            timestamp: DateTime.now(),
          ),
        ],
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final aiProvider = NotifierProvider<AiNotifier, AiState>(AiNotifier.new);
