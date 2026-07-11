import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

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
    test('stamps user_version to current schemaVersion on init', () {
      final version = vectorStore.db!
          .select('PRAGMA user_version')
          .first
          .values
          .first as int;
      expect(version, VectorStore.schemaVersion);
      expect(VectorStore.schemaVersion, greaterThanOrEqualTo(1));
    });

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
      test('content_hash has a UNIQUE index', () {
        final rows = vectorStore.db!.select(
          "SELECT sql FROM sqlite_master WHERE type='index' "
          "AND tbl_name='documents' AND sql LIKE '%content_hash%'",
        );
        final hasUnique = rows.any(
          (r) => (r['sql'] as String).toUpperCase().contains('UNIQUE'),
        );
        expect(hasUnique, isTrue);
      });

      test('v2 migration removes duplicate documents and their vectors',
          () async {
        vectorStore.close();

        final dbFile = File('vectors.db');
        if (dbFile.existsSync()) {
          dbFile.deleteSync();
        }

        final oldDb = sqlite3.open('vectors.db');
        oldDb
          ..execute('''
            CREATE TABLE vectors (
              id TEXT PRIMARY KEY,
              document_id TEXT NOT NULL,
              content TEXT NOT NULL,
              embedding TEXT NOT NULL,
              metadata TEXT,
              created_at INTEGER NOT NULL
            )
          ''')
          ..execute('''
            CREATE TABLE documents (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              file_path TEXT NOT NULL,
              format TEXT NOT NULL,
              chunk_count INTEGER NOT NULL,
              total_characters INTEGER NOT NULL,
              content_hash TEXT NOT NULL,
              ingested_at INTEGER NOT NULL,
              last_refreshed INTEGER,
              status TEXT DEFAULT 'complete',
              contextual_retrieval INTEGER DEFAULT 0,
              error_message TEXT
            )
          ''')
          ..execute(
            'CREATE INDEX idx_documents_hash ON documents(content_hash)',
          )
          ..execute('''
            INSERT INTO documents (
              id, title, file_path, format, chunk_count, total_characters,
              content_hash, ingested_at
            ) VALUES
              ('keep', 'Keep', '/keep.txt', 'plainText', 1, 4, 'same', 1),
              ('drop', 'Drop', '/drop.txt', 'plainText', 1, 4, 'same', 2)
          ''')
          ..execute('''
            INSERT INTO vectors (
              id, document_id, content, embedding, metadata, created_at
            ) VALUES
              ('vec_keep', 'keep', 'kept', '[1.0]', '{}', 1),
              ('vec_drop', 'drop', 'dropped', '[1.0]', '{}', 2)
          ''')
          ..execute('PRAGMA user_version = 1')
          ..close();

        vectorStore = VectorStore();
        await vectorStore.initialize();

        expect(vectorStore.getDocument('keep'), isNotNull);
        expect(vectorStore.getDocument('drop'), isNull);
        expect(vectorStore.getChunksForDocument('keep'), hasLength(1));
        expect(vectorStore.getChunksForDocument('drop'), isEmpty);

        final rows = vectorStore.db!.select(
          "SELECT sql FROM sqlite_master WHERE type='index' "
          "AND name='idx_documents_hash'",
        );
        expect(rows.single['sql'] as String, contains('UNIQUE'));
      });

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

    test('semantic search skips rows with mismatched embedding dimension',
        () async {
      vectorStore.insertEmbedding(
        id: 'ok',
        documentId: 'd',
        content: 'good row',
        embedding: [0.1, 0.2, 0.3],
      );
      vectorStore.insertEmbedding(
        id: 'bad',
        documentId: 'd',
        content: 'wrong dim',
        embedding: [0.1, 0.2],
      );

      final results = await vectorStore.hybridSearch(
        'query',
        [0.1, 0.2, 0.3],
        limit: 5,
        semanticWeight: 1,
      );

      expect(results.map((r) => r.id), contains('ok'));
      expect(results.map((r) => r.id), isNot(contains('bad')));
    });
  });
}
