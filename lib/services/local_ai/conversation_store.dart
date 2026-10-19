/// Local, offline conversation storage for the AI chat.
///
/// The embedded runtime means chat works with no backend at all, so the
/// conversations have to live on the device. Previously they came from
/// `GET /api/ai/conversations`; that endpoint is still there (the desktop app
/// and older clients use it) but mobile no longer depends on it.
///
/// One JSON file, written atomically: a crash mid-save leaves the previous
/// good file rather than a truncated one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ai_models.dart';

class ConversationStore {
  ConversationStore({Directory? directory}) : _directoryOverride = directory;

  static const int _formatVersion = 1;

  final Directory? _directoryOverride;
  File? _file;

  final List<AiConversation> _conversations = [];
  String? _currentConversationId;

  bool _initialized = false;

  /// Conversations, most recently updated first.
  List<AiConversation> get conversations => List.unmodifiable(_conversations);

  String? get currentConversationId => _currentConversationId;

  bool get isInitialized => _initialized;

  /// Loads the file if there is one. Safe to call more than once.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final directory = _directoryOverride ??
          Directory('${(await getApplicationSupportDirectory()).path}/ai');
      await directory.create(recursive: true);
      final file = File('${directory.path}/ai_conversations.json');
      _file = file;

      if (!await file.exists()) return;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final list = decoded['conversations'];
      if (list is List) {
        for (final entry in list) {
          if (entry is Map) {
            final conversation =
                AiConversation.fromJson(Map<String, dynamic>.from(entry));
            if (conversation.id.isNotEmpty) {
              _conversations.add(conversation);
            }
          }
        }
      }

      final current = decoded['currentConversationId'];
      if (current is String &&
          _conversations.any((c) => c.id == current)) {
        _currentConversationId = current;
      }

      _sort();
    } catch (_) {
      // A corrupt or unreadable file should never stop chat from working: fall
      // back to an empty history and let the next save rewrite the file.
      _conversations.clear();
      _currentConversationId = null;
    }
  }

  /// Inserts or replaces [conversation], then persists.
  Future<void> save(AiConversation conversation) async {
    final index = _conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      _conversations[index] = conversation;
    } else {
      _conversations.add(conversation);
    }
    _sort();
    await _persist();
  }

  Future<void> delete(String id) async {
    final removed = _conversations.length;
    _conversations.removeWhere((c) => c.id == id);
    if (_conversations.length == removed) return;

    if (_currentConversationId == id) {
      _currentConversationId =
          _conversations.isEmpty ? null : _conversations.first.id;
    }
    await _persist();
  }

  Future<void> clear() async {
    if (_conversations.isEmpty && _currentConversationId == null) return;
    _conversations.clear();
    _currentConversationId = null;
    await _persist();
  }

  /// Remembers which conversation the user was last looking at.
  Future<void> setCurrentConversation(String? id) async {
    if (_currentConversationId == id) return;
    _currentConversationId = id;
    await _persist();
  }

  AiConversation? findById(String id) {
    for (final conversation in _conversations) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  void _sort() {
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;

    final payload = jsonEncode({
      'version': _formatVersion,
      'currentConversationId': _currentConversationId,
      'conversations': _conversations.map((c) => c.toJson()).toList(),
    });

    // Write to a temp file first, then swap: a crash leaves the previous good
    // file intact instead of a half-written one.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }
}
