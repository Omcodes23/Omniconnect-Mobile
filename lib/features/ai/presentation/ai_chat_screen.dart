import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/ai_provider.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final aiState = ref.read(aiProvider);
    if (aiState.currentConversationId == null) {
      // Auto-create a conversation using first few words as title
      final title = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      ref.read(aiProvider.notifier).createConversation(title);
    }

    ref.read(aiProvider.notifier).sendMessage(text);
    _messageController.clear();
    Future.delayed(const Duration(milliseconds: 200), () {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showNewConversationDialog() {
    _titleController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('New Conversation',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Conversation title',
              hintStyle: TextStyle(color: AppTheme.textMuted),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppTheme.linearGradient(),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextButton(
              onPressed: () {
                final title = _titleController.text.trim();
                if (title.isNotEmpty) {
                  ref.read(aiProvider.notifier).createConversation(title);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Create',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('AI Chat',
            style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        actions: [
          // Model selector
          PopupMenuButton<String>(
            initialValue: aiState.selectedModel,
            onSelected: (model) {
              ref.read(aiProvider.notifier).selectModel(model);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'OpenAI',
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: aiState.selectedModel == 'OpenAI'
                          ? AppTheme.primaryIndigo
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OpenAI',
                      style: TextStyle(
                        color: aiState.selectedModel == 'OpenAI'
                            ? AppTheme.primaryIndigo
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'Gemini',
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: aiState.selectedModel == 'Gemini'
                          ? AppTheme.primaryIndigo
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Gemini',
                      style: TextStyle(
                        color: aiState.selectedModel == 'Gemini'
                            ? AppTheme.primaryIndigo
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'Local',
                child: Row(
                  children: [
                    Icon(
                      Icons.computer_rounded,
                      size: 18,
                      color: aiState.selectedModel == 'Local'
                          ? AppTheme.primaryIndigo
                          : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Local',
                      style: TextStyle(
                        color: aiState.selectedModel == 'Local'
                            ? AppTheme.primaryIndigo
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 16, color: AppTheme.primaryIndigo),
                  const SizedBox(width: 4),
                  Text(
                    aiState.selectedModel,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.primaryIndigo),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded,
                      size: 16, color: AppTheme.primaryIndigo),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.add_rounded,
                  color: AppTheme.primaryIndigo),
              onPressed: _showNewConversationDialog,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Conversation list (horizontal scrollable chips)
          if (aiState.conversations.isNotEmpty)
            Container(
              height: 48,
              color: AppTheme.surface,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: aiState.conversations.length,
                itemBuilder: (context, index) {
                  final conv = aiState.conversations[index];
                  final isActive = conv.id == aiState.currentConversationId;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        conv.title,
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      selected: isActive,
                      selectedColor: AppTheme.primaryIndigo,
                      backgroundColor: AppTheme.surfaceElevated,
                      onSelected: (_) {
                        ref
                            .read(aiProvider.notifier)
                            .selectConversation(conv.id);
                      },
                    ),
                  );
                },
              ),
            ),
          // Messages
          Expanded(
            child: aiState.currentConversationId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 64,
                            color: AppTheme.textMuted.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text(
                          'Start a conversation\nwith AI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppTheme.linearGradient(),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _showNewConversationDialog,
                            icon: const Icon(Icons.add_rounded,
                                color: Colors.white),
                            label: const Text('New Conversation',
                                style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : aiState.currentMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'Send a message to start chatting',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: aiState.currentMessages.length,
                        itemBuilder: (context, index) {
                          final msg = aiState.currentMessages[index];
                          final isUser = msg.role == 'user';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isUser) ...[
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor:
                                        AppTheme.primaryIndigo.withValues(alpha: 0.15),
                                    child: const Icon(Icons.auto_awesome_rounded,
                                        size: 16, color: AppTheme.primaryIndigo),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (isUser) const Spacer(),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      gradient: isUser
                                          ? AppTheme.linearGradient()
                                          : null,
                                      color: isUser
                                          ? null
                                          : AppTheme.surface,
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      border: isUser
                                          ? null
                                          : Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.06)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isUser ? 'You' : 'AI',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isUser
                                                ? Colors.white70
                                                : AppTheme.primaryIndigo,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          msg.content,
                                          style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!isUser) const Spacer(),
                                if (isUser) ...[
                                  const SizedBox(width: 8),
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor:
                                        AppTheme.primaryIndigo.withValues(alpha: 0.15),
                                    child: const Icon(Icons.person_rounded,
                                        size: 16, color: AppTheme.primaryIndigo),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (aiState.isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(
                color: AppTheme.primaryIndigo,
              ),
            ),
          if (aiState.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                aiState.error!,
                style: const TextStyle(
                    color: AppTheme.error, fontSize: 12),
              ),
            ),
          // Input
          Container(
            padding: const EdgeInsets.all(12),
            color: AppTheme.surface,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Ask AI anything...',
                          hintStyle: TextStyle(
                              color: AppTheme.textMuted, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppTheme.linearGradient(),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap:
                            aiState.isLoading ? null : _sendMessage,
                        borderRadius: BorderRadius.circular(12),
                        child: const Center(
                          child: Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
