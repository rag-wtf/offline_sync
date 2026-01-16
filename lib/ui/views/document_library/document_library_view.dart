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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 80,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No documents ingested yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).disabledColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add PDF, DOCX, Markdown, or Text files\n'
            'to start chatting with your data.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).disabledColor,
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
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: viewModel.documents.length,
      itemBuilder: (context, index) {
        final doc = viewModel.documents[index];
        return Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            await viewModel.deleteDocument(doc);
            // If delete was successful (and VM updated),
            // the item is removed.
            // We return false here because the VM handles the refresh/state
            // update which will rebuild the list. Returning true would try
            // to remove it from the tree immediately which might conflict
            // if VM is busy.
            // Actually, usually in standard Dismissible you return true.
            // But since we have an async delete confirmation...
            // Let's rely on VM state.
            return false;
          },
          child: ListTile(
            leading: _buildFormatIcon(context, doc.format),
            title: Text(
              doc.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildStatusBadge(context, doc.status),
                    const SizedBox(width: 8),
                    Text(
                      '${doc.chunkCount} chunks • '
                      '${DateFormat.yMMMd().format(doc.ingestedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (doc.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      doc.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => viewModel.showDocumentDetails(doc),
            ),
            onTap: () => viewModel.showDocumentDetails(doc),
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
        color = Colors.red;
      case DocumentFormat.docx:
        icon = Icons.description;
        color = Colors.blue;
      case DocumentFormat.epub:
        icon = Icons.book;
        color = Colors.orange;
      case DocumentFormat.markdown:
        icon = Icons.code; // or data_object
        color = Colors.teal;
      case DocumentFormat.plainText:
      case DocumentFormat.unknown:
        icon = Icons.article;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
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
        label = 'Processing...';
      case IngestionStatus.complete:
        color = Colors.green;
        label = 'Ready';
      case IngestionStatus.error:
        color = Colors.red;
        label = 'Failed';
    }

    if (status == IngestionStatus.complete) {
      // Don't show badge if ready, to keep it clean, maybe just green dot?
      // Or simply nothing if it's the standard state.
      // But let's show a small dot.
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
