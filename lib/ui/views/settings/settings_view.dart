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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Model Management Section
          const Text(
            'AI Model Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...viewModel.models.map(
            (model) => _ModelTile(
              model: model,
              onDownload: () => viewModel.downloadModel(model.id),
            ),
          ),

          // RAG Quality Settings Section
          const SizedBox(height: 32),
          const Text(
            'RAG Quality Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Improve retrieval accuracy and response quality',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Query Expansion Toggle
          SwitchListTile(
            title: const Text('Query Expansion'),
            subtitle: const Text(
              'Generate query variants for better recall',
            ),
            value: viewModel.queryExpansionEnabled,
            onChanged: viewModel.toggleQueryExpansion,
          ),

          // LLM Reranking Toggle
          SwitchListTile(
            title: const Text('LLM Reranking'),
            subtitle: const Text(
              'Use AI to reorder results by relevance (adds latency)',
            ),
            value: viewModel.rerankingEnabled,
            onChanged: viewModel.toggleReranking,
          ),

          // Contextual Retrieval Toggle
          SwitchListTile(
            title: const Text('Contextual Retrieval'),
            subtitle: const Text(
              'Add context to document chunks for better retrieval (adds time)',
            ),
            value: viewModel.contextualRetrievalEnabled,
            onChanged: viewModel.toggleContextualRetrieval,
          ),

          const SizedBox(height: 16),

          // Chunk Overlap Slider
          ListTile(
            title: Text(
              'Chunk Overlap: '
              '${viewModel.chunkOverlapPercent.toStringAsFixed(0)}%',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Slider(
                  value: viewModel.chunkOverlapPercent,
                  max: 30,
                  divisions: 6,
                  label: '${viewModel.chunkOverlapPercent.toStringAsFixed(0)}%',
                  onChanged: viewModel.setChunkOverlap,
                ),
                const Text(
                  'Overlap between text chunks for better context continuity',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Semantic Weight Slider
          ListTile(
            title: Text(
              'Semantic vs Keyword: '
              '${(viewModel.semanticWeight * 100).toStringAsFixed(0)}%',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Slider(
                  value: viewModel.semanticWeight,
                  divisions: 10,
                  label:
                      '${(viewModel.semanticWeight * 100).toStringAsFixed(0)}%',
                  onChanged: viewModel.setSemanticWeight,
                ),
                const Text(
                  'Balance between semantic search (left) and keyword '
                  'search (right)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Token Management Section
          const SizedBox(height: 32),
          const Text(
            'Token Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Control context and history to fit within model limits',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Search Top K Slider
          ListTile(
            title: Text(
              'Search Top K: ${viewModel.searchTopK}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Slider(
                  value: viewModel.searchTopK.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '${viewModel.searchTopK}',
                  onChanged: viewModel.setSearchTopK,
                ),
                const Text(
                  'Number of context chunks retrieved from vector search',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Max History Messages Slider
          ListTile(
            title: Text(
              'Max History Messages: ${viewModel.maxHistoryMessages}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Slider(
                  value: viewModel.maxHistoryMessages.toDouble(),
                  max: 5,
                  divisions: 5,
                  label: '${viewModel.maxHistoryMessages}',
                  onChanged: viewModel.setMaxHistoryMessages,
                ),
                const Text(
                  'Maximum conversation history messages included in context',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Max Tokens Slider
          ListTile(
            title: Text(
              viewModel.isMaxTokensCustom
                  ? 'Max Tokens: ${viewModel.maxTokens} (Custom)'
                  : 'Max Tokens: ${viewModel.maxTokens} '
                        '(Default)',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Slider(
                  value: viewModel.maxTokens.toDouble(),
                  min: 512,
                  max: 8192,
                  divisions: 15,
                  label: '${viewModel.maxTokens}',
                  onChanged: viewModel.setMaxTokens,
                ),
                Text(
                  viewModel.isMaxTokensCustom
                      ? 'Custom value '
                            '(default: ${viewModel.modelDefaultMaxTokens})'
                      : 'Maximum context window for the model '
                            '(input + output)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          const Divider(height: 32),

          ListTile(
            title: const Text('Manage Knowledge Base'),
            subtitle: const Text('Add, view, and delete documents'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: viewModel.navigateToDocumentLibrary,
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

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.onDownload});
  final ModelInfo model;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(model.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${model.status.name.toUpperCase()}'),
            if (model.status == ModelStatus.downloading)
              LinearProgressIndicator(value: model.progress),
          ],
        ),
        trailing:
            model.status == ModelStatus.notDownloaded ||
                model.status == ModelStatus.error
            ? IconButton(
                icon: Icon(
                  model.status == ModelStatus.error
                      ? Icons.refresh
                      : Icons.download,
                  color: model.status == ModelStatus.error ? Colors.red : null,
                ),
                onPressed: onDownload,
              )
            : model.status == ModelStatus.downloaded
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
      ),
    );
  }
}
