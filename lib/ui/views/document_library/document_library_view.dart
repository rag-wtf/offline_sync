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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        elevation: 0,
        scrolledUnderElevation: 4,
        actions: [
          if (viewModel.isIngesting)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: viewModel.pickAndIngestFile,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Document'),
        elevation: 2,
      ),
      body: viewModel.isBusy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading documents...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : viewModel.documents.isEmpty
          ? _buildEmptyState(context)
          : _buildDocumentList(context, viewModel),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.library_books_outlined,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No documents yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add PDF, DOCX, Markdown, or Text files\n'
              'to start chatting with your data.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Tap the button below to get started',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentList(
    BuildContext context,
    DocumentLibraryViewModel viewModel,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: viewModel.documents.length,
      itemBuilder: (context, index) {
        final doc = viewModel.documents[index];
        return Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colorScheme.error,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(
              Icons.delete_rounded,
              color: colorScheme.onError,
            ),
          ),
          confirmDismiss: (direction) async {
            await viewModel.deleteDocument(doc);
            return false;
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => viewModel.showDocumentDetails(doc),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildStatusBadge(context, doc.status),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${doc.chunkCount} chunks • '
                                  '${DateFormat.yMMMd().format(
                                    doc.ingestedAt,
                                  )}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (doc.errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                doc.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.error,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.outline,
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
    final colorScheme = Theme.of(context).colorScheme;

    IconData icon;
    Color color;

    switch (format) {
      case DocumentFormat.pdf:
        icon = Icons.picture_as_pdf_rounded;
        color = Colors.red;
      case DocumentFormat.docx:
        icon = Icons.description_rounded;
        color = Colors.blue;
      case DocumentFormat.epub:
        icon = Icons.book_rounded;
        color = Colors.orange;
      case DocumentFormat.markdown:
        icon = Icons.code_rounded;
        color = Colors.teal;
      case DocumentFormat.plainText:
      case DocumentFormat.unknown:
        icon = Icons.article_rounded;
        color = colorScheme.outline;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildStatusBadge(BuildContext context, IngestionStatus status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color color;
    String label;
    IconData? icon;

    switch (status) {
      case IngestionStatus.pending:
        color = colorScheme.outline;
        label = 'Pending';
        icon = Icons.hourglass_empty_rounded;
      case IngestionStatus.processing:
        color = colorScheme.primary;
        label = 'Processing';
        icon = Icons.sync_rounded;
      case IngestionStatus.complete:
        color = Colors.green;
        label = 'Ready';
        icon = Icons.check_circle_rounded;
      case IngestionStatus.error:
        color = colorScheme.error;
        label = 'Failed';
        icon = Icons.error_rounded;
      case IngestionStatus.cancelled:
        color = Colors.orange;
        label = 'Cancelled';
        icon = Icons.cancel_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
