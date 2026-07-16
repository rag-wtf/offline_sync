import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/vector_store.dart'; // For EmbeddingData
import 'package:stacked/stacked.dart';

class DocumentDetailViewModel extends BaseViewModel {
  final DocumentManagementService _documentService =
      locator<DocumentManagementService>();

  Document? _document;
  Document? get document => _document;

  List<EmbeddingData> _chunks = [];
  List<EmbeddingData> get chunks => _chunks;

  Future<void> initialize(Document doc) async {
    _document = doc;
    setBusy(true);
    _chunks = await _documentService.getDocumentChunks(doc.id);
    setBusy(false);
  }
}
