import 'package:file_picker/file_picker.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class DocumentLibraryViewModel extends BaseViewModel {
  final DocumentManagementService _documentService =
      locator<DocumentManagementService>();
  final NavigationService _navigationService = locator<NavigationService>();
  final DialogService _dialogService = locator<DialogService>();

  List<Document> _documents = [];
  List<Document> get documents => _documents;

  // Track active ingestion progress per document
  final Map<String, IngestionProgress> _activeIngestions = {};
  Map<String, IngestionProgress> get activeIngestions => _activeIngestions;

  bool get isIngesting => _activeIngestions.isNotEmpty;

  Future<void> initialize() async {
    setBusy(true);
    await _refreshDocuments();
    setBusy(false);

    // Listen to progress stream to update UI in real-time
    _documentService.ingestionProgressStream.listen((event) async {
      // Update active ingestion tracking
      if (event.stage == 'complete' || event.stage == 'error') {
        // Keep the final state briefly before removing
        _activeIngestions[event.documentId] = event;
        notifyListeners();

        // Wait a moment to show completion/error, then remove
        await Future<void>.delayed(const Duration(seconds: 2));
        _activeIngestions.remove(event.documentId);

        await _refreshDocuments();
        if (event.stage == 'error') {
          await _dialogService.showDialog(
            title: 'Ingestion Error',
            description: 'Failed to process ${event.documentTitle}.',
          );
        }
      } else {
        // Update progress for ongoing ingestion
        _activeIngestions[event.documentId] = event;
      }
      notifyListeners();
    });
  }

  Future<void> _refreshDocuments() async {
    _documents = await _documentService.getAllDocuments();
    notifyListeners();
  }

  Future<void> pickAndIngestFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'epub', 'json'],
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        try {
          await _documentService.addDocumentFromPlatformFile(file);
        } on Exception catch (e) {
          await _dialogService.showDialog(
            title: 'Error',
            description: 'Failed to add ${file.name}: $e',
          );
        }
      }

      await _refreshDocuments();
    }
  }

  Future<void> deleteDocument(Document doc) async {
    final response = await _dialogService.showConfirmationDialog(
      title: 'Delete Document?',
      description:
          'Are you sure you want to delete "${doc.title}"? '
          'This will remove all associated knowledge chunks.',
      confirmationTitle: 'Delete',
    );

    if (response?.confirmed ?? false) {
      setBusy(true);
      await _documentService.deleteDocument(doc.id);
      await _refreshDocuments();
      setBusy(false);
    }
  }

  Future<void> showDocumentDetails(Document doc) async {
    await _navigationService.navigateTo<dynamic>(
      Routes.documentDetailView,
      arguments: DocumentDetailViewArguments(document: doc),
    );
  }
}
