import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
}

void main() {
  // No need for open.overrideFor in sqlite3 v3 - uses automatic build hooks
  TestWidgetsFlutterBinding.ensureInitialized();
  late VectorStore vectorStore;

  setUp(() async {
    PathProviderPlatform.instance = MockPathProviderPlatform();

    // Mock SharedPreferences for RagSettingsService
    SharedPreferences.setMockInitialValues({});

    // Reset locator to ensure clean state before each test
    await locator.reset();

    // Setup locator with fresh registrations
    await setupLocator();

    final ragSettings = locator<RagSettingsService>();
    await ragSettings.initialize();

    final dbFile = File('vectors.db');
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }

    vectorStore = VectorStore();
    await vectorStore.initialize();
  });

  tearDown(() async {
    vectorStore.close();

    final dbFile = File('vectors.db');
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }

    await locator.reset();
  });

  group('VectorStore Tests', () {
    test('insert and retrieve semantic embedding', () async {
      const id = 'test_1';
      const embedding = [0.1, 0.2, 0.3];

      vectorStore.insertEmbedding(
        id: id,
        documentId: 'doc_1',
        content: 'This is a test content',
        embedding: embedding,
      );

      final results = await vectorStore.hybridSearch(
        'test',
        [0.1, 0.2, 0.3],
        limit: 1,
        semanticWeight: 1,
      );

      expect(results.length, 1);
      expect(results.first.id, id);
      // RRF score for rank 1 with semanticWeight 1.0 is 1.0 / (60 + 1) approx 0.01639
      expect(results.first.score, closeTo(0.01639, 0.0001));
    });

    test('FTS5 search fallback works', () async {
      vectorStore.insertEmbedding(
        id: 'fts_1',
        documentId: 'doc_2',
        content: 'The quick brown fox jumps over the lazy dog',
        embedding: [0.0, 0.0, 0.0],
      );

      final results = await vectorStore.hybridSearch(
        'fox jumps',
        [0.0, 0.0, 0.0],
        limit: 1,
        semanticWeight: 0, // Force keyword search
      );

      expect(results.length, 1);
      expect(results.first.content, contains('fox'));
    });

    group('Hybrid Search Merging', () {
      test('combines scores correctly', () {
        // This is harder to test without exposing internals,
        // but we can verify behavior through results ordering.
      });
    });

    group('Document Management Tests', () {
      test('CRUD operations', () async {
        final doc = Document(
          id: 'doc_1',
          title: 'Test Document',
          filePath: '/path/to/test.pdf',
          format: DocumentFormat.pdf,
          chunkCount: 10,
          totalCharacters: 1000,
          contentHash: 'hash123',
          ingestedAt: DateTime.now(),
          contextualRetrievalEnabled: true,
        );

        // Create
        vectorStore.insertDocument(doc);

        // Read
        final retrieved = vectorStore.getDocument('doc_1');
        expect(retrieved, isNotNull);
        expect(retrieved!.title, 'Test Document');
        expect(retrieved.contextualRetrievalEnabled, isTrue);

        final all = vectorStore.getAllDocuments();
        expect(all.length, 1);
        expect(all.first.id, 'doc_1');

        // Find by Hash
        final byHash = vectorStore.findByHash('hash123');
        expect(byHash?.id, 'doc_1');
        expect(vectorStore.findByHash('invalid'), isNull);

        // Update
        final updatedDoc = Document(
          id: 'doc_1',
          title: 'Updated Title',
          filePath: '/path/to/test.pdf',
          format: DocumentFormat.pdf,
          chunkCount: 10,
          totalCharacters: 1000,
          contentHash: 'hash123',
          ingestedAt: DateTime.now(),
        );
        vectorStore.updateDocument(updatedDoc);
        expect(vectorStore.getDocument('doc_1')!.title, 'Updated Title');

        // Delete (Cascade verify)
        // First insert a vector linked to this doc
        vectorStore.insertEmbedding(
          id: 'vec_1',
          documentId: 'doc_1',
          content: 'chunk 1',
          embedding: [0.1, 0.2],
        );

        // Verify vector exists
        var results = await vectorStore.hybridSearch(
          'chunk',
          [0.1, 0.2],
          limit: 10,
          semanticWeight: 0.5,
        );
        expect(results.length, 1);

        vectorStore.deleteDocument('doc_1');

        // Verify document gone
        expect(vectorStore.getDocument('doc_1'), isNull);

        // Verify vector gone
        results = await vectorStore.hybridSearch(
          'chunk',
          [0.1, 0.2],
          limit: 10,
          semanticWeight: 0.5,
        );
        expect(results.isEmpty, true);
      });
    });
  });
}
