/// Conversation + message models for the on-device AI chat.
///
/// These used to live in `ai_provider.dart`. They moved here so the local
/// conversation store can use them without importing the provider (which would
/// be a circular import). `ai_provider.dart` re-exports this file, so every
/// existing `import '.../services/ai_provider.dart';` keeps working unchanged.
library;

class AiMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;

  AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
        id: json['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
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

  /// Always `'local'` for the embedded runtime. Kept as a field so existing
  /// persisted conversations (and the desktop backend's JSON shape) still map.
  final String provider;

  /// The local model id (e.g. `qwen2.5-1.5b-instruct-q4km`) that produced the
  /// replies, or `'local'` if it was never recorded.
  final String modelName;

  final List<AiMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiConversation({
    required this.id,
    required this.title,
    this.provider = 'local',
    this.modelName = 'local',
    this.messages = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  AiConversation copyWith({
    String? id,
    String? title,
    String? provider,
    String? modelName,
    List<AiMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      AiConversation(
        id: id ?? this.id,
        title: title ?? this.title,
        provider: provider ?? this.provider,
        modelName: modelName ?? this.modelName,
        messages: messages ?? this.messages,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'provider': provider,
        'modelName': modelName,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
        id: json['id']?.toString() ?? '',
        title: json['title'] ?? 'Untitled',
        provider: json['provider'] ?? 'local',
        modelName: json['modelName'] ?? 'local',
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}
