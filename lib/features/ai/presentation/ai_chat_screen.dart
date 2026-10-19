import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/ai_provider.dart';

/// The AI chat screen.
///
/// There is no provider to choose from any more: the model list *is* the model
/// picker. Everything the user can do here is local — pick a model, let it
/// download once, then chat. Companion mode is the single switch that needs the
/// desktop backend, and it says so plainly when that backend is not running.
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

    // The provider creates the conversation on the first message and derives its
    // title from the text, so there is nothing to pre-create here.
    ref.read(aiProvider.notifier).sendMessage(text);
    _messageController.clear();
    _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), _scrollToBottom);
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

  // ── Model picker sheet ────────────────────────────────────────────────────

  void _showModelSheet() {
    final notifier = ref.read(aiProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final state = ref.watch(aiProvider);
            final statuses = state.models;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.memory_rounded,
                            size: 20, color: AppTheme.primaryIndigo),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Local model',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: AppTheme.textMuted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Text(
                      'Runs entirely on this device. Nothing is sent to a '
                      'server.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: statuses.length,
                        itemBuilder: (ctx, index) {
                          final status = statuses[index];
                          final entry = status.entry;
                          final isActive = entry.id == state.activeModelId;
                          return _ModelTile(
                            status: status,
                            isActive: isActive,
                            onSelect: () {
                              notifier.selectModel(entry.id);
                              Navigator.pop(ctx);
                            },
                            onDownload: () => notifier.startDownload(entry.id),
                            onCancel: () => notifier.cancelDownload(entry.id),
                            onDelete: () => notifier.deleteModel(entry.id),
                          );
                        },
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    _CompanionRow(state: state, notifier: notifier),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  Widget _modelButton(AiState state) {
    final label = state.activeModel?.entry.displayName ?? 'Select model';
    final ready = state.hasReadyModel;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showModelSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ready ? Icons.memory_rounded : Icons.download_rounded,
                size: 16,
                color: AppTheme.primaryIndigo,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryIndigo,
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded,
                  size: 16, color: AppTheme.primaryIndigo),
            ],
          ),
        ),
      ),
    );
  }

  Widget _companionButton(AiState state) {
    final enabled = state.companionEnabled;
    return IconButton(
      tooltip: 'Companion mode — ${_companionLabel(state.companionStatus)}',
      onPressed: state.companionStatus == 'loading'
          ? null
          : () => ref
              .read(aiProvider.notifier)
              .setCompanionEnabled(!enabled),
      icon: Icon(
        enabled ? Icons.people_alt_rounded : Icons.people_alt_outlined,
        color: enabled ? AppTheme.primaryIndigo : AppTheme.textMuted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiProvider);

    // Keep the newest content visible while a reply streams in.
    ref.listen<AiState>(aiProvider, (previous, next) {
      if (next.currentMessages.length != (previous?.currentMessages.length ?? 0) ||
          next.streamingReply != previous?.streamingReply) {
        _scheduleScrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('AI Chat',
            style: TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        actions: [
          _modelButton(aiState),
          _companionButton(aiState),
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
          _StatusBanner(
            state: aiState,
            onPickModel: _showModelSheet,
            onCancelDownload: () {
              final id = aiState.downloadingModelId;
              if (id != null) {
                ref.read(aiProvider.notifier).cancelDownload(id);
              }
            },
          ),
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
                          color: isActive ? Colors.white : AppTheme.textMuted,
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
          Expanded(child: _buildMessages(aiState)),
          if (aiState.isLoading && !aiState.isStreaming)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(color: AppTheme.primaryIndigo),
            ),
          if (aiState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      aiState.error!,
                      style: const TextStyle(
                          color: AppTheme.error, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: AppTheme.textMuted),
                    onPressed: () => ref.read(aiProvider.notifier).clearError(),
                  ),
                ],
              ),
            ),
          _buildInput(aiState),
        ],
      ),
    );
  }

  Widget _buildMessages(AiState aiState) {
    final streaming = aiState.isStreaming ? aiState.streamingReply : null;

    if (aiState.currentConversationId == null && streaming == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 64,
                  color: AppTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                aiState.runtimeAvailable
                    ? 'Chat with a model that runs\nentirely on this device'
                    : 'Local AI runtime is not installed',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              if (aiState.runtimeAvailable && !aiState.hasReadyModel)
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.linearGradient(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _showModelSheet,
                    icon: const Icon(Icons.download_rounded,
                        color: Colors.white),
                    label: const Text('Choose a model',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                )
              else if (aiState.hasReadyModel)
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.linearGradient(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _showNewConversationDialog,
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
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
        ),
      );
    }

    if (aiState.currentMessages.isEmpty && streaming == null) {
      return const Center(
        child: Text(
          'Send a message to start chatting',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final itemCount = aiState.currentMessages.length + (streaming != null ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final isStreamingBubble = streaming != null &&
            index == aiState.currentMessages.length;
        final msg = isStreamingBubble ? null : aiState.currentMessages[index];
        final role = isStreamingBubble ? 'assistant' : msg!.role;
        final content = isStreamingBubble ? streaming : msg!.content;
        return _MessageBubble(
          role: role,
          content: content,
          streaming: isStreamingBubble,
        );
      },
    );
  }

  Widget _buildInput(AiState aiState) {
    final canSend = !aiState.isGenerating;
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.surface,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Ask AI anything...',
                    hintStyle:
                        TextStyle(color: AppTheme.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  onTap: !canSend
                      ? null
                      : aiState.isStreaming
                          ? () => ref.read(aiProvider.notifier).cancelGeneration()
                          : _sendMessage,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Icon(
                      aiState.isStreaming
                          ? Icons.stop_rounded
                          : Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

String _companionLabel(String status) {
  switch (status) {
    case 'online':
      return 'online — others can message it';
    case 'offline':
      return 'off';
    case 'no-model':
      return 'no model ready';
    case 'loading':
      return 'working...';
    case 'unknown':
      return 'needs OmniConnect Desktop';
    default:
      return status;
  }
}

/// Top-of-screen summary: the runtime warning, or the download/prepare state of
/// the selected model. Hidden once a model is ready and the runtime is present.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.state,
    required this.onPickModel,
    required this.onCancelDownload,
  });

  final AiState state;
  final VoidCallback onPickModel;
  final VoidCallback onCancelDownload;

  @override
  Widget build(BuildContext context) {
    if (!state.runtimeAvailable) {
      return _banner(
        icon: Icons.error_outline_rounded,
        color: AppTheme.error,
        title: 'Local AI runtime not installed',
        body: 'This build has no embedded llama.cpp library. Build the native '
            'library with native/build-android.ps1 and rebuild the app.',
      );
    }

    final downloading = state.downloadingModelId != null;
    if (downloading) {
      final status = state.activeModel;
      final label = status?.entry.displayName ??
          ModelCatalog.find(state.downloadingModelId)?.displayName ??
          'model';
      return Container(
        width: double.infinity,
        color: AppTheme.surfaceElevated,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded,
                    size: 16, color: AppTheme.primaryIndigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Downloading $label',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppTheme.textMuted),
                  onPressed: onCancelDownload,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(
                value: state.downloadProgress == 0 ? null : state.downloadProgress,
                color: AppTheme.primaryIndigo,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(state.downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%  •  one-time download, then chat works offline',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (!state.hasReadyModel) {
      return _banner(
        icon: Icons.memory_rounded,
        color: AppTheme.primaryIndigo,
        title: 'Select a model to begin',
        body: 'Choose one small model, download it once, and it runs here on '
            'your device — no account, no server.',
        action: TextButton(
          onPressed: onPickModel,
          child: const Text('Choose model',
              style: TextStyle(color: AppTheme.primaryIndigo)),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      color: AppTheme.surfaceElevated,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
    this.streaming = false,
  });

  final String role;
  final String content;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.15),
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
                gradient: isUser ? AppTheme.linearGradient() : null,
                color: isUser ? null : AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: isUser
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'You' : 'AI',
                    style: TextStyle(
                      fontSize: 11,
                      color: isUser ? Colors.white70 : AppTheme.primaryIndigo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content.isEmpty && streaming ? '…' : content,
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
              backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded,
                  size: 16, color: AppTheme.primaryIndigo),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.status,
    required this.isActive,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final LocalModelStatus status;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final entry = status.entry;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppTheme.primaryIndigo.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded,
                              size: 14, color: AppTheme.primaryIndigo),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.quantization}  •  ${entry.sizeLabel}  •  ${entry.contextLength} ctx',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _trailing(),
            ],
          ),
          if (status.isDownloading) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(
                value: status.downloadProgress == 0
                    ? null
                    : status.downloadProgress,
                color: AppTheme.primaryIndigo,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ],
          if (status.error != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                status.error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              entry.description,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trailing() {
    if (status.isDownloading) {
      return TextButton(
        onPressed: onCancel,
        child: const Text('Cancel',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      );
    }
    if (status.isDownloaded) {
      if (isActive) {
        return IconButton(
          tooltip: 'Delete from this device',
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: AppTheme.textMuted),
          onPressed: onDelete,
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: onSelect,
            child: const Text('Use',
                style: TextStyle(color: AppTheme.primaryIndigo, fontSize: 12)),
          ),
          IconButton(
            tooltip: 'Delete from this device',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppTheme.textMuted),
            onPressed: onDelete,
          ),
        ],
      );
    }
    return TextButton.icon(
      onPressed: onDownload,
      icon: const Icon(Icons.download_rounded,
          size: 16, color: AppTheme.primaryIndigo),
      label: const Text('Download',
          style: TextStyle(color: AppTheme.primaryIndigo, fontSize: 12)),
    );
  }
}

class _CompanionRow extends StatelessWidget {
  const _CompanionRow({required this.state, required this.notifier});

  final AiState state;
  final AiNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final busy = state.companionStatus == 'loading';
    final reachable = state.companionStatus != 'unknown';
    return Row(
      children: [
        const Icon(Icons.people_alt_outlined,
            size: 20, color: AppTheme.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Companion mode',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              ),
              Text(
                reachable
                    ? _companionLabel(state.companionStatus)
                    : 'Available when OmniConnect Desktop is running.',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        if (busy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primaryIndigo),
          )
        else
          Switch(
            value: state.companionEnabled,
            activeThumbColor: AppTheme.primaryIndigo,
            onChanged: (v) => notifier.setCompanionEnabled(v),
          ),
      ],
    );
  }
}
