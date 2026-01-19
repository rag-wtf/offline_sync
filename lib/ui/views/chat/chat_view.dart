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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    unawaited(
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.filter_list_rounded, color: colorScheme.primary),
              const SizedBox(width: 12),
              const Flexible(
                child: Text('Filter by Documents'),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: viewModel.availableDocuments.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        size: 48,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No documents available.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : ListenableBuilder(
                    listenable: viewModel,
                    builder: (context, child) {
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: viewModel.availableDocuments.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = viewModel.availableDocuments[index];
                          final isSelected = viewModel.selectedDocumentIds
                              .contains(
                                doc.id,
                              );
                          return CheckboxListTile(
                            title: Text(
                              doc.title,
                              style: theme.textTheme.bodyLarge,
                            ),
                            subtitle: Text(
                              doc.format.name.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                            value: isSelected,
                            onChanged: (_) =>
                                viewModel.toggleDocumentSelection(doc.id),
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            activeColor: colorScheme.primary,
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            FilledButton(
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Listen for message changes to scroll
    if (viewModel.shouldScroll) {
      _scrollToBottom(viewModel);
      viewModel.onScrolled();
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 20,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            const Text('RAG Sync Chat'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: viewModel.navigateToSettings,
            tooltip: 'Settings',
          ),
        ],
        elevation: 0,
        scrolledUnderElevation: 4,
      ),
      body: Column(
        children: [
          Expanded(
            child: viewModel.isBusy
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : viewModel.messages.isEmpty
                ? _buildEmptyChat(context)
                : ListView.builder(
                    controller: viewModel.scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: viewModel.messages.length,
                    itemBuilder: (context, index) {
                      final message = viewModel.messages[index];
                      return _MessageTile(
                        message: message,
                        onSourceClick: viewModel.showSourceDetail,
                      );
                    },
                  ),
          ),
          if (viewModel.isProcessing)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
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

  Widget _buildEmptyChat(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Start a conversation',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask questions about your documents\n'
              'or upload new ones to get started.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
    final colorScheme = theme.colorScheme;

    final isUser = message.isUser;
    final bubbleColor = isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor = isUser ? colorScheme.onPrimary : colorScheme.onSurface;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
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
                          height: 1.4,
                        ),
                      ),
                    ),
                    // Show blinking cursor for empty or streaming AI messages
                    if (!isUser && message.content.isEmpty)
                      _BlinkingCursor(color: textColor),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (!isUser && message.sources != null && message.sources!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.source_outlined,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sources',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: message.sources!.map((source) {
                      final title =
                          source.metadata['documentTitle'] as String? ??
                          'Source';
                      return ActionChip(
                        label: Text(
                          title,
                          style: theme.textTheme.labelSmall,
                        ),
                        avatar: Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                        onPressed: () => onSourceClick?.call(source),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: colorScheme.outlineVariant,
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
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
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
  final _focusNode = FocusNode();

  void _handleSend() {
    if (_controller.text.isEmpty) return;
    widget.onSend(_controller.text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Filter button
            Stack(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: widget.hasActiveFilters
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
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
                        color: colorScheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            // Attach button
            IconButton(
              icon: Icon(
                Icons.attach_file_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: widget.onAttach,
              tooltip: 'Attach document',
            ),
            // Text input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Ask about your documents...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: theme.textTheme.bodyMedium,
                  onSubmitted: (_) => _handleSend(),
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: IconButton.filled(
                icon: Icon(
                  Icons.send_rounded,
                  color: widget.isProcessing
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onPrimary,
                ),
                onPressed: widget.isProcessing ? null : _handleSend,
                style: IconButton.styleFrom(
                  backgroundColor: widget.isProcessing
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primary,
                  disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
