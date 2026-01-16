import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/contextual_retrieval_service.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/smart_chunker.dart';
import 'package:offline_sync/services/vector_store.dart';

import '../helpers/test_helpers.dart';

// ... other imports

class MockVectorStore extends Mock implements VectorStore {}

class MockDocumentParserService extends Mock implements DocumentParserService {}

class MockSmartChunker extends Mock implements SmartChunker {}

class MockEmbeddingService extends Mock implements EmbeddingService {}

class MockContextualRetrievalService extends Mock
    implements ContextualRetrievalService {}

void main() {
  late DocumentManagementService service;
  late MockVectorStore mockVectorStore;
  late MockDocumentParserService mockParserService;
  late MockSmartChunker mockSmartChunker;
  late MockEmbeddingService mockEmbeddingService;
  late MockRagSettingsService mockSettingsService;
  late MockContextualRetrievalService mockContextualRetrievalService;

  setUpAll(() {
    registerFallbackValue(
      Document(
        id: 'fallback',
        title: 'fallback',
        filePath: 'fallback',
        format: DocumentFormat.plainText,
        chunkCount: 0,
        totalCharacters: 0,
        contentHash: 'fallback',
        ingestedAt: DateTime.now(),
      ),
    );
    // Register generic definition for EmbeddingData list
    registerFallbackValue(<EmbeddingData>[]);
  });

  setUp(() async {
    await locator.reset();

    mockVectorStore = MockVectorStore();
    mockParserService = MockDocumentParserService();
    mockSmartChunker = MockSmartChunker();
    mockEmbeddingService = MockEmbeddingService();
    mockSettingsService = getAndRegisterMockRagSettingsService();
    mockContextualRetrievalService = MockContextualRetrievalService();

    locator
      ..registerSingleton<VectorStore>(mockVectorStore)
      ..registerSingleton<DocumentParserService>(mockParserService)
      ..registerSingleton<SmartChunker>(mockSmartChunker)
      ..registerSingleton<EmbeddingService>(mockEmbeddingService)
      ..registerSingleton<ContextualRetrievalService>(
        mockContextualRetrievalService,
      );

    // Set default settings
    when(() => mockSettingsService.maxDocumentSizeMB).thenReturn(10);
    when(
      () => mockSettingsService.contextualRetrievalEnabled,
    ).thenReturn(false);

    // Default contextual retrieval behavior
    when(
      () => mockContextualRetrievalService.isSupported,
    ).thenAnswer((_) async => false);

    service = DocumentManagementService();
  });

  group('DocumentManagementService Tests', () {
    test('addDocument success flow', () async {
      final file = File('test_file.txt');
      await file.writeAsString('Test content');

      // Mocks
      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      // NOTE: parseDocument and chunk are called in isolate on REAL instances,
      // so mocks are not called.
      // But we still need to mock dependencies of addDocument that run in main
      // isolate.

      when(
        () => mockEmbeddingService.generateEmbedding(any<String>()),
      ).thenAnswer((_) async => [0.1, 0.2]);
      when(() => mockVectorStore.findByHash(any<String>())).thenReturn(null);
      // Need to verify insert calls
      when(
        () => mockVectorStore.insertDocument(any<Document>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.updateDocument(any<Document>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.insertEmbeddingsBatch(any<List<EmbeddingData>>()),
      ).thenReturn(null);

      // Execute
      final result = await service.addDocument(file.path);

      // Verify
      expect(result.title, 'test_file.txt');
      expect(result.status, IngestionStatus.complete);

      // detectFormat IS called in main isolate
      verify(() => mockParserService.detectFormat(file.path)).called(1);

      // parseDocument and chunk are NOT called on mocks due to isolate usage
      // verify(() => mockParserService.parseDocument(file.path)).called(1);
      // verify(() => mockSmartChunker.chunk('Test content')).called(1);

      verify(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
        ), // chunk content might vary slightly due to real parser
      ).called(1);
      verify(
        () => mockVectorStore.insertEmbeddingsBatch(any<List<EmbeddingData>>()),
      ).called(1);

      // Cleanup
      await file.delete();
    });

    // ... existing tests ...
    test('addDocument detects duplicates', () async {
      final file = File('test_dup.txt');
      await file.writeAsString('Duplicate content');

      final existing = Document(
        id: 'existing_id',
        title: 'existing',
        filePath: 'path',
        format: DocumentFormat.plainText,
        chunkCount: 1,
        totalCharacters: 10,
        // Real hash will differ but logic uses what findByHash returns
        contentHash: 'hash',
        ingestedAt: DateTime.now(),
      );

      when(
        () => mockVectorStore.findByHash(any<String>()),
      ).thenReturn(existing);

      final result = await service.addDocument(file.path);

      expect(result.id, 'existing_id');
      verifyNever(() => mockParserService.parseDocument(any<String>()));

      await file.delete();
    });

    test('addDocument respects size limit', () async {
      final file = File('large_file.txt');
      // Create a dummy file, but we mock the size check by calling a file
      // that doesn't exist?
      // No, create a real file but set max size small.
      await file.writeAsString('Large content');

      when(
        () => mockSettingsService.maxDocumentSizeMB,
      ).thenReturn(0); // Tiny limit (0 means >0 fails)

      expect(
        () => service.addDocument(file.path),
        throwsA(isA<Exception>()),
      );

      await file.delete();
    });
  });
}
