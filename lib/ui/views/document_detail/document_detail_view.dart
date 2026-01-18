import 'package:flutter/material.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/ui/views/document_detail/document_detail_viewmodel.dart';
import 'package:stacked/stacked.dart';

class DocumentDetailView extends StackedView<DocumentDetailViewModel> {
  const DocumentDetailView({required this.document, super.key});

  final Document document;

  @override
  Widget builder(
    BuildContext context,
    DocumentDetailViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
      ),
      body: viewModel.isBusy
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(context, viewModel),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: viewModel.chunks.length,
                    itemBuilder: (context, index) {
                      final chunk = viewModel.chunks[index];
                      return ExpansionTile(
                        title: Text(
                          'Chunk ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          chunk.content.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Content:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(chunk.content),
                                const SizedBox(height: 16),
                                const Text(
                                  'Metadata:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(chunk.metadata.toString()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context, DocumentDetailViewModel viewModel) {
    final doc = viewModel.document ?? document;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                context,
                'Format',
                doc.format.name.toUpperCase(),
                Icons.extension,
              ),
              _buildInfoItem(
                context,
                'Status',
                doc.status.name.toUpperCase(),
                Icons.sync,
              ),
              _buildInfoItem(
                context,
                'Chunks',
                '${doc.chunkCount}',
                Icons.pie_chart,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    doc.filePath,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  DocumentDetailViewModel viewModelBuilder(BuildContext context) =>
      DocumentDetailViewModel();

  @override
  void onViewModelReady(DocumentDetailViewModel viewModel) =>
      viewModel.initialize(document);
}
