import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/ui/views/document_library/document_library_viewmodel.dart';
import 'package:stacked/stacked.dart';

class DocumentLibraryView extends StackedView<DocumentLibraryViewModel> {
  const DocumentLibraryView({super.key});

  @override
  Widget builder(
    BuildContext context,
    DocumentLibraryViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        actions: [
          if (viewModel.isIngesting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: viewModel.pickAndIngestFile,
        icon: const Icon(Icons.add),
        label: const Text('Add Document'),
      ),
      body: viewModel.isBusy
          ? const Center(child: CircularProgressIndicator())
          : viewModel.documents.isEmpty
          ? _buildEmptyState(context)
          : _buildDocumentList(context, viewModel),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.library_books_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No documents yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Add PDF, DOCX, Markdown, or Text files\n'
              'to start chatting with your data.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentList(
    BuildContext context,
    DocumentLibraryViewModel viewModel,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: viewModel.documents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = viewModel.documents[index];
        return Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            await viewModel.deleteDocument(doc);
            return false;
          },
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: InkWell(
              onTap: () => viewModel.showDocumentDetails(doc),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _buildFormatIcon(context, doc.format),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildStatusBadge(context, doc.status),
                              const SizedBox(width: 8),
                              Text(
                                '${doc.chunkCount} chunks',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                ' • ${DateFormat.yMMMd().format(
                                  doc.ingestedAt,
                                )}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => viewModel.showDocumentDetails(doc),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormatIcon(BuildContext context, DocumentFormat format) {
    IconData icon;
    Color color;

    switch (format) {
      case DocumentFormat.pdf:
        icon = Icons.picture_as_pdf;
        color = const Color(0xFFF40F02);
      case DocumentFormat.docx:
        icon = Icons.description;
        color = const Color(0xFF2B579A);
      case DocumentFormat.epub:
        icon = Icons.book;
        color = const Color(0xFFFDD835);
      case DocumentFormat.markdown:
        icon = Icons.code;
        color = const Color(0xFF009688);
      case DocumentFormat.plainText:
      case DocumentFormat.unknown:
        icon = Icons.article;
        color = const Color(0xFF9E9E9E);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildStatusBadge(BuildContext context, IngestionStatus status) {
    Color color;
    String label;

    switch (status) {
      case IngestionStatus.pending:
        color = Colors.grey;
        label = 'Pending';
      case IngestionStatus.processing:
        color = Colors.blue;
        label = 'Processing';
      case IngestionStatus.complete:
        color = Colors.green;
        label = 'Ready';
      case IngestionStatus.error:
        color = Colors.red;
        label = 'Failed';
    }

    if (status == IngestionStatus.complete) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  DocumentLibraryViewModel viewModelBuilder(BuildContext context) =>
      DocumentLibraryViewModel();

  @override
  void onViewModelReady(DocumentLibraryViewModel viewModel) =>
      viewModel.initialize();
}
