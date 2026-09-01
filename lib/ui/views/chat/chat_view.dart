import 'dart:async';
import 'package:flutter/material.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:offline_sync/ui/views/chat/widgets/chat_input.dart';
import 'package:offline_sync/ui/views/chat/widgets/chat_message_tile.dart';
import 'package:stacked/stacked.dart';

class ChatView extends StackedView<ChatViewModel> {
  const ChatView({this.viewModel, this.onViewModelReadyCallback, super.key});

  final ChatViewModel? viewModel;
  final void Function(ChatViewModel viewModel)? onViewModelReadyCallback;

  void _scrollToBottom(ChatViewModel viewModel) {
    if (viewModel.scrollController.hasClients) {
      unawaited(
        viewModel.scrollController.animateTo(
          viewModel.scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
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
              const SizedBox(width: 12),
              Flexible(
                child: Text(AppLocalizations.of(context).filterByDocuments),
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
                        AppLocalizations.of(context).noDocumentsAvailable,
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
                        // coverage:ignore-start
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        // coverage:ignore-end
                        itemBuilder: (context, index) {
                          final doc = viewModel.availableDocuments[index];
                          final isSelected = viewModel.selectedDocumentIds
                              .contains(doc.id);
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
              child: Text(AppLocalizations.of(context).done),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (viewModel.shouldScroll) {
        _scrollToBottom(viewModel);
        viewModel.onScrolled();
      }
    });

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
            Text(AppLocalizations.of(context).ragSyncChatTitle),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: viewModel.navigateToSettings,
            tooltip: AppLocalizations.of(context).settingsTooltip,
          ),
        ],
        elevation: 0,
        scrolledUnderElevation: 4,
      ),
      body: Column(
        children: [
          if (viewModel.isIngesting ||
              viewModel.currentIngestionProgress != null)
            _buildIngestionProgress(context, viewModel),
          Expanded(
            child: viewModel.isBusy
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).loading,
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
                      return ChatMessageTile(
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
          ChatInput(
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

  Widget _buildIngestionProgress(
    BuildContext context,
    ChatViewModel viewModel,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = viewModel.currentIngestionProgress;
    final title = progress?.documentTitle.isNotEmpty == true
        ? progress!.documentTitle
        : 'Document';
    final stage = progress?.stage ?? 'Processing';
    final percent = (progress != null && progress.totalChunks > 0)
        ? (progress.currentChunk / progress.totalChunks)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.25),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: (percent != null && percent > 0) ? percent : null,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ingesting $title ($stage)...',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (percent != null && percent > 0)
                Text(
                  '${(percent * 100).toInt()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percent != null && percent > 0) ? percent : null,
              minHeight: 4,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
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
              AppLocalizations.of(context).startConversation,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).startConversationSubtitle,
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
  ChatViewModel viewModelBuilder(BuildContext context) =>
      viewModel ?? ChatViewModel();

  @override
  void onViewModelReady(ChatViewModel viewModel) {
    final callback = onViewModelReadyCallback;
    if (callback != null) {
      callback(viewModel);
      return;
    }
    unawaited(viewModel.initialize());
  }
}
