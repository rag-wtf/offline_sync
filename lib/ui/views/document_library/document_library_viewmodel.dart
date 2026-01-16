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

  bool _isIngesting = false;
  bool get isIngesting => _isIngesting;

  Future<void> initialize() async {
    setBusy(true);
    await _refreshDocuments();
    setBusy(false);

    // Listen to progress stream to update UI in real-time
    _documentService.ingestionProgressStream.listen((event) async {
      if (event.stage == 'complete' || event.stage == 'error') {
        await _refreshDocuments();
        if (event.stage == 'error') {
          await _dialogService.showDialog(
            title: 'Ingestion Error',
            description: 'Failed to process ${event.documentTitle}.',
          );
        }
      }
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
      _isIngesting = true;
      notifyListeners();

      for (final file in result.files) {
        if (file.path != null) {
          try {
            await _documentService.addDocument(file.path!);
          } on Exception catch (e) {
            await _dialogService.showDialog(
              title: 'Error',
              description: 'Failed to add ${file.name}: $e',
            );
          }
        }
      }

      await _refreshDocuments();
      _isIngesting = false;
      notifyListeners();
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
