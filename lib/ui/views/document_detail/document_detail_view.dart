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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoItem(context, 'Format', doc.format.name.toUpperCase()),
              _buildInfoItem(context, 'Status', doc.status.name.toUpperCase()),
              _buildInfoItem(context, 'Chunks', '${doc.chunkCount}'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.folder_open, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.filePath,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
