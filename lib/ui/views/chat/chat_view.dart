import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  @override
  Widget builder(BuildContext context, ChatViewModel viewModel, Widget? child) {
    // Listen for message changes to scroll
    if (viewModel.shouldScroll) {
      _scrollToBottom(viewModel);
      viewModel.onScrolled();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RAG Sync Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: viewModel.navigateToSettings,
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
                    padding: const EdgeInsets.all(16),
                    itemCount: viewModel.messages.length,
                    itemBuilder: (context, index) {
                      final message = viewModel.messages[index];
                      return _MessageTile(message: message);
                    },
                  ),
          ),
          if (viewModel.isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          _ChatInput(
            onSend: viewModel.sendMessage,
            onAttach: viewModel.pickAndIngestFiles,
            isProcessing: viewModel.isProcessing,
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
  const _MessageTile({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = message.isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = message.isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final align = message.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
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
                        style: TextStyle(color: textColor),
                      ),
                    ),
                    // Show blinking cursor for empty or streaming AI messages
                    if (!message.isUser && message.content.isEmpty)
                      _BlinkingCursor(color: textColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (!message.isUser &&
              message.sources != null &&
              message.sources!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'Sources: ${message.sources!.length} chunks retrieved',
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
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
    required this.isProcessing,
  });
  final void Function(String) onSend;
  final VoidCallback onAttach;
  final bool isProcessing;

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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: widget.onAttach,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Ask about your documents...',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: widget.isProcessing ? null : _handleSend,
            ),
          ],
        ),
      ),
    );
  }
}
