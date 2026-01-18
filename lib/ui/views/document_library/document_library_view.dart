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
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Knowledge Base',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          if (viewModel.isIngesting)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: viewModel.pickAndIngestFile,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Document'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.library_books_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No documents yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add PDF, DOCX, EPUB, or Text files to start\n'
            'chatting with your knowledge base.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: viewModel.documents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = viewModel.documents[index];
        return Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onError,
            ),
          ),
          confirmDismiss: (direction) async {
            await viewModel.deleteDocument(doc);
            return false;
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: _buildFormatIcon(context, doc.format),
              title: Text(
                doc.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildStatusBadge(context, doc.status),
                      const SizedBox(width: 8),
                      Text(
                        '${doc.chunkCount} chunks',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat.yMMMd().format(doc.ingestedAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (doc.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 14,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doc.errorMessage!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onPressed: () => viewModel.showDocumentDetails(doc),
              ),
              onTap: () => viewModel.showDocumentDetails(doc),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
        icon = Icons.picture_as_pdf_outlined;
        color = Colors.red.shade400;
      case DocumentFormat.docx:
        icon = Icons.description_outlined;
        color = Colors.blue.shade400;
      case DocumentFormat.epub:
        icon = Icons.local_library_outlined;
        color = Colors.orange.shade400;
      case DocumentFormat.markdown:
        icon = Icons.code;
        color = Colors.teal.shade400;
      case DocumentFormat.plainText:
      case DocumentFormat.unknown:
        icon = Icons.article_outlined;
        color = Colors.grey.shade500;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildStatusBadge(BuildContext context, IngestionStatus status) {
    Color color;
    String label;

    switch (status) {
      case IngestionStatus.pending:
        color = Theme.of(context).colorScheme.outline;
        label = 'Pending';
      case IngestionStatus.processing:
        color = Theme.of(context).colorScheme.primary;
        label = 'Processing';
      case IngestionStatus.complete:
        color = Colors.green.shade600;
        label = 'Ready';
      case IngestionStatus.error:
        color = Theme.of(context).colorScheme.error;
        label = 'Failed';
    }

    if (status == IngestionStatus.complete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
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
