import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:stacked/stacked.dart';

class ChatView extends StackedView<ChatViewModel> {
  const ChatView({super.key});

  void _scrollToBottom(ChatViewModel viewModel) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (viewModel.scrollController.hasClients) {
        unawaited(
          viewModel.scrollController.animateTo(
            viewModel.scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _showFilterDialog(BuildContext context, ChatViewModel viewModel) {
    unawaited(
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Filter by Documents'),
          content: SizedBox(
            width: double.maxFinite,
            child: viewModel.availableDocuments.isEmpty
                ? const Text('No documents available.')
                : ViewModelBuilder<ChatViewModel>.reactive(
                    viewModelBuilder: () => viewModel,
                    disposeViewModel: false, // Don't dispose parent VM
                    builder: (context, model, child) {
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: model.availableDocuments.length,
                        itemBuilder: (context, index) {
                          final doc = model.availableDocuments[index];
                          final isSelected = model.selectedDocumentIds.contains(
                            doc.id,
                          );
                          return CheckboxListTile(
                            title: Text(doc.title),
                            subtitle: Text(
                              doc.format.name.toUpperCase(),
                              style: const TextStyle(fontSize: 10),
                            ),
                            value: isSelected,
                            onChanged: (_) =>
                                model.toggleDocumentSelection(doc.id),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget builder(BuildContext context, ChatViewModel viewModel, Widget? child) {
    // Listen for message changes to scroll
    if (viewModel.shouldScroll) {
      _scrollToBottom(viewModel);
      viewModel.onScrolled();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'RAG Sync Chat',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: viewModel.navigateToSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: viewModel.isBusy
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: viewModel.scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    itemCount: viewModel.messages.length,
                    itemBuilder: (context, index) {
                      final message = viewModel.messages[index];
                      // Improve spacing between messages
                      final isLastMessage =
                          index == viewModel.messages.length - 1;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: isLastMessage ? 16 : 0,
                        ),
                        child: _MessageTile(
                          message: message,
                          onSourceClick: viewModel.showSourceDetail,
                        ),
                      );
                    },
                  ),
          ),
          if (viewModel.isProcessing)
            const Padding(
              padding: EdgeInsets.zero,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _ChatInput(
            onSend: viewModel.sendMessage,
            onAttach: viewModel.pickAndIngestFiles,
            onFilter: () => _showFilterDialog(context, viewModel),
            isProcessing: viewModel.isProcessing,
            hasActiveFilters: viewModel.selectedDocumentIds.isNotEmpty,
          ),
        ],
      ),
    );
  }

  @override
  ChatViewModel viewModelBuilder(BuildContext context) => ChatViewModel();

  @override
  void onViewModelReady(ChatViewModel viewModel) {
    unawaited(viewModel.initialize());
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    this.onSourceClick,
  });
  final ChatMessage message;
  final void Function(SearchResult)? onSourceClick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    final color = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.secondaryContainer.withValues(alpha: 0.5);

    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSecondaryContainer;

    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
      bottomRight: isUser ? Radius.zero : const Radius.circular(16),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (!isUser && message.content.isEmpty)
                      _BlinkingCursor(color: textColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (!isUser && message.sources != null && message.sources!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sources',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: message.sources!.map((source) {
                      final title =
                          source.metadata['documentTitle'] as String? ??
                          'Source';
                      return InkWell(
                        onTap: () => onSourceClick?.call(source),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  title,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor({required this.color});
  final Color color;

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 530),
      vsync: this,
    );
    unawaited(_controller.repeat(reverse: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 16,
        margin: const EdgeInsets.only(left: 2),
        color: widget.color,
      ),
    );
  }
}

class _ChatInput extends StatefulWidget {
  const _ChatInput({
    required this.onSend,
    required this.onAttach,
    required this.onFilter,
    required this.isProcessing,
    required this.hasActiveFilters,
  });
  final void Function(String) onSend;
  final VoidCallback onAttach;
  final VoidCallback onFilter;
  final bool isProcessing;
  final bool hasActiveFilters;

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final _controller = TextEditingController();

  void _handleSend() {
    if (_controller.text.isEmpty) return;
    widget.onSend(_controller.text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Stack(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: widget.hasActiveFilters
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: widget.onFilter,
                  tooltip: 'Filter documents',
                ),
                if (widget.hasActiveFilters)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: widget.onAttach,
              tooltip: 'Add documents',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Ask a question...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: theme.textTheme.bodyMedium,
                  onSubmitted: (_) => _handleSend(),
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.arrow_upward_rounded),
              onPressed: widget.isProcessing ? null : _handleSend,
              tooltip: 'Send message',
            ),
          ],
        ),
      ),
    );
  }
}
