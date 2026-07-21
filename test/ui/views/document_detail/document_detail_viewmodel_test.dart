import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/document_detail/document_detail_viewmodel.dart';

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

void main() {
  late MockDocumentManagementService documentService;
  late Document document;
  late EmbeddingData chunk;

  setUp(() {
    documentService = MockDocumentManagementService();
    document = Document(
      id: 'doc-1',
      title: 'Doc',
      filePath: '/tmp/doc.md',
      format: DocumentFormat.markdown,
      chunkCount: 1,
      totalCharacters: 12,
      contentHash: 'hash',
      ingestedAt: DateTime(2024),
      status: IngestionStatus.complete,
    );
    chunk = EmbeddingData(
      id: 'chunk-1',
      documentId: 'doc-1',
      content: 'Chunk body',
      embedding: const [0.1, 0.2],
      metadata: const {'page': 1},
    );

    locator.registerSingleton<DocumentManagementService>(documentService);
    when(() => documentService.getDocumentChunks(document.id)).thenAnswer(
      (_) async => [chunk],
    );
  });

  tearDown(locator.reset);

  test('initialize loads document chunks and clears busy state', () async {
    final viewModel = DocumentDetailViewModel();

    final future = viewModel.initialize(document);
    expect(viewModel.isBusy, isTrue);

    await future;

    expect(viewModel.isBusy, isFalse);
    expect(viewModel.document, document);
    expect(viewModel.chunks, [chunk]);
  });
}
