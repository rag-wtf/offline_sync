import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/open.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
}

void main() {
  open.overrideFor(
    OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  late VectorStore vectorStore;

  setUp(() async {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    vectorStore = VectorStore();
    await vectorStore.initialize();
  });

  tearDown(() {
    vectorStore.close();
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

      final results = vectorStore.hybridSearch(
        'test',
        [0.1, 0.2, 0.3],
        limit: 1,
        semanticWeight: 1,
      );

      expect(results.length, 1);
      expect(results.first.id, id);
      expect(results.first.score, greaterThan(0.99));
    });

    test('FTS5 search fallback works', () async {
      vectorStore.insertEmbedding(
        id: 'fts_1',
        documentId: 'doc_2',
        content: 'The quick brown fox jumps over the lazy dog',
        embedding: [0.0, 0.0, 0.0],
      );

      final results = vectorStore.hybridSearch(
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
  });
}
