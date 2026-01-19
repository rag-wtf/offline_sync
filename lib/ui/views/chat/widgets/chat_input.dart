import 'package:flutter/material.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    required this.onSend,
    required this.onAttach,
    required this.onFilter,
    required this.isProcessing,
    required this.hasActiveFilters,
    super.key,
  });
  final void Function(String) onSend;
  final VoidCallback onAttach;
  final VoidCallback onFilter;
  final bool isProcessing;
  final bool hasActiveFilters;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
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
                  tooltip: AppLocalizations.of(context).filterByDocuments,
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
              tooltip: AppLocalizations.of(context).attachDocument,
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
                    hintText: AppLocalizations.of(context).chatInputHint,
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
                      ? colorScheme.onPrimary
                      : colorScheme.onPrimary,
                ),
                onPressed: widget.isProcessing ? null : _handleSend,
                style: IconButton.styleFrom(
                  backgroundColor: widget.isProcessing
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.primary,
                  disabledBackgroundColor: colorScheme.primary.withValues(
                    alpha: 0.5,
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
