import 'package:flutter/material.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/settings/settings_viewmodel.dart';
import 'package:stacked/stacked.dart';

class SettingsView extends StackedView<SettingsViewModel> {
  const SettingsView({super.key});

  @override
  Widget builder(
    BuildContext context,
    SettingsViewModel viewModel,
    Widget? child,
  ) {
    final theme = Theme.of(context);
    final chunkOverlap = viewModel.chunkOverlapPercent.toStringAsFixed(0);
    final semanticWeight = (viewModel.semanticWeight * 100).toStringAsFixed(0);
    final maxTokensLabel = viewModel.isMaxTokensCustom
        ? 'Max Tokens (Custom)'
        : 'Max Tokens (Default)';
    final maxTokensDesc = viewModel.isMaxTokensCustom
        ? 'Custom (default: ${viewModel.modelDefaultMaxTokens})'
        : 'Maximum context window for the model';
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(title: 'AI Model Management'),
          ...viewModel.models.map(
            (model) => _ModelTile(
              model: model,
              onDownload: () => viewModel.downloadModel(model.id),
            ),
          ),
          const SizedBox(height: 32),

          const _SectionHeader(title: 'RAG Quality Settings'),
          const SizedBox(height: 8),
          Text(
            'Improve retrieval accuracy and response quality',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainer,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Query Expansion'),
                  subtitle: const Text(
                    'Generate query variants for better recall',
                  ),
                  value: viewModel.queryExpansionEnabled,
                  onChanged: viewModel.toggleQueryExpansion,
                  secondary: Icon(
                    Icons.saved_search,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                SwitchListTile(
                  title: const Text('LLM Reranking'),
                  subtitle: const Text(
                    'Use AI to reorder results by relevance',
                  ),
                  value: viewModel.rerankingEnabled,
                  onChanged: viewModel.toggleReranking,
                  secondary: Icon(Icons.sort, color: theme.colorScheme.primary),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                SwitchListTile(
                  title: const Text('Contextual Retrieval'),
                  subtitle: const Text(
                    'Add context to chunks for better retrieval',
                  ),
                  value: viewModel.contextualRetrievalEnabled,
                  onChanged: viewModel.toggleContextualRetrieval,
                  secondary: Icon(
                    Icons.content_paste_search,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainer,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chunk Overlap',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '$chunkOverlap%',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: viewModel.chunkOverlapPercent,
                        max: 30,
                        divisions: 6,
                        label: '$chunkOverlap%',
                        onChanged: viewModel.setChunkOverlap,
                      ),
                      Text(
                        'Overlap between text chunks context continuity',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Semantic vs Keyword',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '$semanticWeight%',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: viewModel.semanticWeight,
                        divisions: 10,
                        label: '$semanticWeight%',
                        onChanged: viewModel.setSemanticWeight,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Keyword', style: theme.textTheme.bodySmall),
                          Text('Semantic', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const _SectionHeader(title: 'Token Management'),
          const SizedBox(height: 8),
          Text(
            'Control context and history to fit within model limits',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainer,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Search Top K',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${viewModel.searchTopK}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: viewModel.searchTopK.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: '${viewModel.searchTopK}',
                        onChanged: viewModel.setSearchTopK,
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Max History Messages',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${viewModel.maxHistoryMessages}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: viewModel.maxHistoryMessages.toDouble(),
                        max: 5,
                        divisions: 5,
                        label: '${viewModel.maxHistoryMessages}',
                        onChanged: viewModel.setMaxHistoryMessages,
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            maxTokensLabel,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${viewModel.maxTokens}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: viewModel.maxTokens.toDouble(),
                        min: 512,
                        max: 8192,
                        divisions: 15,
                        label: '${viewModel.maxTokens}',
                        onChanged: viewModel.setMaxTokens,
                      ),
                      Text(
                        maxTokensDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          ListTile(
            title: const Text('Manage Knowledge Base'),
            subtitle: const Text('Add, view, and delete documents'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: viewModel.navigateToDocumentLibrary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  SettingsViewModel viewModelBuilder(BuildContext context) =>
      SettingsViewModel();

  @override
  void onViewModelReady(SettingsViewModel viewModel) {
    viewModel.setup();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.onDownload});
  final ModelInfo model;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          model.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      theme,
                      model.status,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    model.status.name.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(theme, model.status),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (model.status == ModelStatus.downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: model.progress,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
        trailing: _buildTrailingAction(theme),
      ),
    );
  }

  Color _getStatusColor(ThemeData theme, ModelStatus status) {
    switch (status) {
      case ModelStatus.notDownloaded:
        return theme.colorScheme.outline;
      case ModelStatus.downloading:
        return theme.colorScheme.primary;
      case ModelStatus.downloaded:
        return Colors.green;
      case ModelStatus.error:
        return theme.colorScheme.error;
    }
  }

  Widget? _buildTrailingAction(ThemeData theme) {
    if (model.status == ModelStatus.downloaded) {
      return Icon(Icons.check_circle_rounded, color: Colors.green.shade600);
    }
    if (model.status == ModelStatus.notDownloaded ||
        model.status == ModelStatus.error) {
      return IconButton.filledTonal(
        icon: Icon(
          model.status == ModelStatus.error
              ? Icons.refresh
              : Icons.download_rounded,
        ),
        onPressed: onDownload,
        color: model.status == ModelStatus.error
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
      );
    }
    return null;
  }
}
