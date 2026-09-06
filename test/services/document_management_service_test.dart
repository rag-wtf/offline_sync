import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
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
import 'package:path/path.dart' as path;

import '../helpers/test_helpers.dart';

// ... other imports

class MockVectorStore extends Mock implements VectorStore {}

class MockDocumentParserService extends Mock implements DocumentParserService {}

class MockSmartChunker extends Mock implements SmartChunker {}

class MockEmbeddingService extends Mock implements EmbeddingService {}

class MockEmbeddingModel extends Mock implements EmbeddingModel {}

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
  late Directory testDirectory;

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
    registerFallbackValue(MockEmbeddingModel());
    // Register generic definition for EmbeddingData list
    registerFallbackValue(<EmbeddingData>[]);
  });

  setUp(() async {
    await locator.reset();
    testDirectory = await Directory.systemTemp.createTemp(
      'offline_sync_document_management_test_',
    );
    addTearDown(() async {
      if (testDirectory.existsSync()) {
        await testDirectory.delete(recursive: true);
      }
    });

    mockVectorStore = MockVectorStore();
    mockParserService = MockDocumentParserService();
    mockSmartChunker = MockSmartChunker();
    mockEmbeddingService = MockEmbeddingService();
    mockSettingsService = getAndRegisterMockRagSettingsService();
    mockContextualRetrievalService = MockContextualRetrievalService();

    final embeddingModel = MockEmbeddingModel();
    when(() => mockEmbeddingService.pinActiveModel()).thenAnswer(
      (_) async => PinnedEmbeddingModel(
        id: 'gecko-64',
        model: embeddingModel,
      ),
    );

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
    test('value objects expose cancellation and aggregate state', () {
      final job = IngestionJob(documentId: 'doc');
      expect(job.isCancelled, isFalse);
      job.cancel();
      expect(job.isCancelled, isTrue);

      const result = IngestionResult(
        succeeded: [],
        failed: {'file.txt': 'failed'},
      );
      expect(result.hasErrors, isTrue);
      expect(result.totalCount, 1);
      expect(
        const IngestionProgress(
          documentId: 'd',
          documentTitle: 'D',
          stage: 'parsing',
        ).currentChunk,
        0,
      );
    });

    test('addDocument rejects a missing file', () async {
      await expectLater(
        service.addDocument('does-not-exist.txt'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('addDocumentFromPlatformFile ingests in-memory bytes', () async {
      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      when(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
        ),
      ).thenAnswer((_) async => [0.1, 0.2]);
      when(() => mockVectorStore.findByHash(any<String>())).thenReturn(null);
      when(
        () => mockVectorStore.insertDocument(any<Document>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.updateDocument(any<Document>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.insertEmbeddingsBatch(any<List<EmbeddingData>>()),
      ).thenReturn(null);

      final result = await service.addDocumentFromPlatformFile(
        FakePlatformFile(
          name: 'memory.txt',
          size: 12,
          bytes: Uint8List.fromList('memory bytes'.codeUnits),
        ),
      );

      expect(result.title, 'memory.txt');
      expect(result.filePath, 'memory.txt');
      expect(result.status, IngestionStatus.complete);
    });

    test('addDocumentFromPlatformFile rejects missing bytes', () async {
      await expectLater(
        service.addDocumentFromPlatformFile(
          FakePlatformFile(name: 'empty.txt'),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('File content is not available'),
          ),
        ),
      );
    });

    test(
      'addMultipleDocuments reports successes and failures per file',
      () async {
        final file = File(
          path.join(testDirectory.path, 'multiple-success.txt'),
        );
        await file.writeAsString('multiple content');
        addTearDown(() async {
          if (file.existsSync()) await file.delete();
        });
        when(() => mockVectorStore.findByHash(any<String>())).thenReturn(null);
        when(
          () => mockParserService.detectFormat(any<String>()),
        ).thenReturn(DocumentFormat.plainText);
        when(
          () => mockEmbeddingService.generateEmbedding(
            any<String>(),
            model: any<EmbeddingModel>(named: 'model'),
          ),
        ).thenAnswer((_) async => [0.1]);
        when(
          () => mockVectorStore.insertDocument(any<Document>()),
        ).thenReturn(null);
        when(
          () => mockVectorStore.updateDocument(any<Document>()),
        ).thenReturn(null);
        when(
          () =>
              mockVectorStore.insertEmbeddingsBatch(any<List<EmbeddingData>>()),
        ).thenReturn(null);

        final result = await service.addMultipleDocuments([
          file.path,
          'missing.txt',
        ]);

        expect(result.succeeded, hasLength(1));
        expect(result.failed.keys, contains('missing.txt'));
        expect(result.totalCount, 2);
      },
    );

    test('delegates document query and maintenance operations', () async {
      final document = Document(
        id: 'doc',
        title: 'Doc',
        filePath: 'doc.txt',
        format: DocumentFormat.plainText,
        chunkCount: 1,
        totalCharacters: 4,
        contentHash: 'hash',
        ingestedAt: DateTime.now(),
      );
      final chunks = [
        EmbeddingData(
          id: 'chunk',
          documentId: 'doc',
          content: 'text',
          embedding: [1],
        ),
      ];
      when(() => mockVectorStore.getAllDocuments()).thenReturn([document]);
      when(() => mockVectorStore.getDocument('doc')).thenReturn(document);
      when(() => mockVectorStore.findByHash('hash')).thenReturn(document);
      when(
        () => mockVectorStore.getChunksForDocument('doc'),
      ).thenReturn(chunks);
      when(() => mockVectorStore.deleteDocument('doc')).thenReturn(null);

      expect(await service.getAllDocuments(), [document]);
      expect(await service.findByHash('hash'), same(document));
      expect(await service.getDocumentChunks('doc'), chunks);
      await service.deleteDocument('doc');
      verify(() => mockVectorStore.deleteDocument('doc')).called(1);
    });

    test('addDocument success flow', () async {
      final file = File(path.join(testDirectory.path, 'test_file.txt'));
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
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
        ),
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
      verify(
        () => mockParserService.detectFormat(path.basename(file.path)),
      ).called(1);

      // parseDocument and chunk are NOT called on mocks due to isolate usage
      // verify(() => mockParserService.parseDocument(file.path)).called(1);
      // verify(() => mockSmartChunker.chunk('Test content')).called(1);

      verify(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
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
      final file = File(path.join(testDirectory.path, 'test_dup.txt'));
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

    test('cleans in-flight hash when initial insert fails', () async {
      final file = File(path.join(testDirectory.path, 'insert_failure.txt'));
      await file.writeAsString('Insert failure content');

      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      when(() => mockVectorStore.findByHash(any<String>())).thenReturn(null);
      when(
        () => mockVectorStore.insertDocument(any<Document>()),
      ).thenThrow(Exception('insert failed'));

      await expectLater(
        service.addDocument(file.path),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        service.addDocument(file.path),
        throwsA(isA<Exception>()),
      );

      verify(() => mockVectorStore.insertDocument(any<Document>())).called(2);

      await file.delete();
    });

    test('addDocument respects size limit', () async {
      final file = File(path.join(testDirectory.path, 'large_file.txt'));
      // Create a dummy file, but we mock the size check by calling a file
      // that doesn't exist?
      // No, create a real file but set max size small.
      await file.writeAsString('Large content');

      when(
        () => mockSettingsService.maxDocumentSizeMB,
      ).thenReturn(0); // Tiny limit (0 means >0 fails)

      expect(() => service.addDocument(file.path), throwsA(isA<Exception>()));

      await file.delete();
    });

    test('formats size-limit values with one stable decimal place', () {
      expect(
        DocumentManagementService.formatFileSizeMB(12.3456789),
        '12.3 MB',
      );
    });

    test('cleans partial vectors when embedding fails', () async {
      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      when(() => mockVectorStore.findByHash(any<String>())).thenReturn(null);
      when(
        () => mockVectorStore.insertDocument(any<Document>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.updateDocument(any<Document>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.insertEmbeddingsBatch(any<List<EmbeddingData>>()),
      ).thenReturn(null);
      when(
        () => mockVectorStore.deleteVectorsForDocument(any<String>()),
      ).thenReturn(null);

      var embeddingCalls = 0;
      when(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
        ),
      ).thenAnswer((_) async {
        embeddingCalls++;
        if (embeddingCalls > 1) throw StateError('embedding failed');
        return [0.1, 0.2];
      });

      await expectLater(
        service.addDocumentFromPlatformFile(
          FakePlatformFile(
            name: 'partial.txt',
            size: 2500,
            bytes: Uint8List.fromList(List<int>.filled(2500, 97)),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      verify(
        () => mockVectorStore.deleteVectorsForDocument(any<String>()),
      ).called(1);
    });

    test(
      'renames a document without changing its identity or vectors',
      () async {
        final document = Document(
          id: 'doc',
          title: 'Old title',
          filePath: '/tmp/doc.txt',
          format: DocumentFormat.plainText,
          chunkCount: 1,
          totalCharacters: 4,
          contentHash: 'hash',
          ingestedAt: DateTime(2024),
        );
        when(() => mockVectorStore.getDocument('doc')).thenReturn(document);

        await service.renameDocument('doc', 'New title');

        verify(
          () => mockVectorStore.renameDocument('doc', 'New title'),
        ).called(1);
      },
    );

    test('addDocumentFromPlatformFile uses path-backed size validation '
        'before reading bytes', () async {
      final file = File(
        path.join(testDirectory.path, 'oversized_platform_file.txt'),
      );
      await file.writeAsString('oversized content');

      when(() => mockSettingsService.maxDocumentSizeMB).thenReturn(0);

      final platformFile = FakePlatformFile(
        path: file.path,
        name: 'oversized_platform_file.txt',
        size: await file.length(),
      );

      await expectLater(
        service.addDocumentFromPlatformFile(platformFile),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('exceeds limit'),
          ),
        ),
      );

      await file.delete();
    });

    test('reindexDocument keeps old document when reingestion fails', () async {
      final file = File(path.join(testDirectory.path, 'refresh_failure.txt'));
      await file.writeAsString('new content');

      final oldDoc = Document(
        id: 'old_doc',
        title: 'Old',
        filePath: file.path,
        format: DocumentFormat.plainText,
        chunkCount: 1,
        totalCharacters: 11,
        contentHash: 'old-hash',
        ingestedAt: DateTime.now(),
      );

      when(() => mockVectorStore.getDocument('old_doc')).thenReturn(oldDoc);
      when(() => mockVectorStore.findByHash(any<String>())).thenReturn(null);
      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      when(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
        ),
      ).thenThrow(StateError('embedding failed'));
      when(
        () => mockVectorStore.insertDocument(any<Document>()),
      ).thenThrow(Exception('insert failed'));

      await expectLater(
        service.reindexDocument('old_doc'),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => mockVectorStore.deleteDocument('old_doc'));

      await file.delete();
    });

    test(
      'reindexDocument does not delete old vectors before success',
      () async {
        final file = File(path.join(testDirectory.path, 'reindex_failure.txt'));
        await file.writeAsString('reindex failure content');

        final oldDoc = Document(
          id: 'old_doc',
          title: 'Old',
          filePath: file.path,
          format: DocumentFormat.plainText,
          chunkCount: 1,
          totalCharacters: 22,
          contentHash: 'old-hash',
          ingestedAt: DateTime.now(),
          status: IngestionStatus.complete,
          embeddingModelId: 'old-model',
        );

        when(() => mockVectorStore.getDocument('old_doc')).thenReturn(oldDoc);
        when(
          () => mockParserService.detectFormat(any<String>()),
        ).thenReturn(DocumentFormat.plainText);
        when(
          () => mockEmbeddingService.generateEmbedding(
            any<String>(),
            model: any<EmbeddingModel>(named: 'model'),
          ),
        ).thenThrow(StateError('embedding failed'));
        when(
          () => mockVectorStore.deleteVectorsForDocument(any<String>()),
        ).thenReturn(null);

        await expectLater(
          service.reindexDocument('old_doc'),
          throwsA(isA<StateError>()),
        );

        verifyNever(() => mockVectorStore.deleteDocument('old_doc'));
        await file.delete();
      },
    );

    test(
      'reindexDocument returns byte-backed documents without refreshing',
      () async {
        final byteBackedDoc = Document(
          id: 'bytes_doc',
          title: 'Bytes Doc',
          filePath: 'bytes_doc.pdf',
          format: DocumentFormat.pdf,
          chunkCount: 1,
          totalCharacters: 128,
          contentHash: 'hash',
          ingestedAt: DateTime.now(),
        );

        when(
          () => mockVectorStore.getDocument('bytes_doc'),
        ).thenReturn(byteBackedDoc);

        final result = await service.reindexDocument('bytes_doc');

        expect(result, same(byteBackedDoc));
        verifyNever(() => mockVectorStore.deleteDocument(any()));
      },
    );

    test('reindexes a pathless document from durable source bytes', () async {
      final oldDocument = Document(
        id: 'bytes-doc',
        title: 'Bytes Doc',
        filePath: 'bytes-doc.txt',
        format: DocumentFormat.plainText,
        chunkCount: 1,
        totalCharacters: 4,
        contentHash: 'old-hash',
        ingestedAt: DateTime.now(),
        status: IngestionStatus.complete,
        embeddingModelId: 'old-model',
        sourceBytes: Uint8List.fromList('new bytes'.codeUnits),
      );

      final embeddingModel = MockEmbeddingModel();
      when(() => mockEmbeddingService.pinActiveModel()).thenAnswer(
        (_) async =>
            PinnedEmbeddingModel(id: 'gecko-64', model: embeddingModel),
      );
      when(
        () => mockVectorStore.getDocument('bytes-doc'),
      ).thenReturn(oldDocument);
      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      when(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
        ),
      ).thenAnswer((_) async => [0.1, 0.2]);
      when(() => mockVectorStore.insertEmbeddingsBatch(any())).thenReturn(null);
      when(
        () => mockVectorStore.deleteVectorsForDocument(any()),
      ).thenReturn(null);

      final result = await service.reindexDocument('bytes-doc');

      expect(result?.id, 'bytes-doc');
      verify(
        () => mockVectorStore.replaceDocument(
          oldDocumentId: 'bytes-doc',
          stagedDocumentId: any(named: 'stagedDocumentId'),
          replacement: any(named: 'replacement'),
        ),
      ).called(1);
    });

    test('propagates staged-vector cleanup failures', () async {
      final oldDocument = Document(
        id: 'cleanup-doc',
        title: 'Cleanup Doc',
        filePath: 'cleanup-doc.txt',
        format: DocumentFormat.plainText,
        chunkCount: 1,
        totalCharacters: 4,
        contentHash: 'old-hash',
        ingestedAt: DateTime.now(),
        status: IngestionStatus.complete,
        embeddingModelId: 'old-model',
        sourceBytes: Uint8List.fromList('cleanup bytes'.codeUnits),
      );
      when(
        () => mockVectorStore.getDocument('cleanup-doc'),
      ).thenReturn(oldDocument);
      when(
        () => mockParserService.detectFormat(any<String>()),
      ).thenReturn(DocumentFormat.plainText);
      when(
        () => mockEmbeddingService.generateEmbedding(
          any<String>(),
          model: any<EmbeddingModel>(named: 'model'),
        ),
      ).thenThrow(StateError('embedding failed'));
      when(
        () => mockVectorStore.deleteVectorsForDocument(any()),
      ).thenThrow(StateError('cleanup failed'));

      await expectLater(
        service.reindexDocument('cleanup-doc'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cleanup failed'),
          ),
        ),
      );
    });
  });
}
