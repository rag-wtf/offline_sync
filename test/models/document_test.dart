import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_parser_service.dart';

void main() {
  test('reports when vectors are not in the active embedding space', () {
    final document = Document(
      id: 'document',
      title: 'Document',
      filePath: 'document.txt',
      format: DocumentFormat.plainText,
      chunkCount: 1,
      totalCharacters: 10,
      contentHash: 'hash',
      ingestedAt: DateTime(2024),
      status: IngestionStatus.complete,
      embeddingModelId: 'model-a',
    );

    expect(document.needsReindex('model-b'), isTrue);
    expect(document.needsReindex('model-a'), isFalse);
    expect(document.needsReindex(null), isTrue);
  });

  group('Document.fromJson -', () {
    test('tolerates missing/null numeric and string fields', () {
      final doc = Document.fromJson(<String, dynamic>{
        'id': 'abc',
        'format': 'pdf',
        'ingested_at': 0,
      });

      expect(doc.id, 'abc');
      expect(doc.title, isNotNull);
      expect(doc.chunkCount, 0);
      expect(doc.totalCharacters, 0);
      expect(doc.contentHash, isNotNull);
    });

    test('falls back for unknown enums and missing refresh timestamp', () {
      final doc = Document.fromJson(<String, dynamic>{
        'id': 'doc-1',
        'title': 'Fallback test',
        'file_path': '/tmp/fallback.txt',
        'format': 'not-a-real-format',
        'chunk_count': 3,
        'total_characters': 42,
        'content_hash': 'hash',
        'ingested_at': 1234,
        'status': 'not-a-real-status',
        'contextual_retrieval': 0,
      });

      expect(doc.format, DocumentFormat.unknown);
      expect(doc.status, IngestionStatus.complete);
      expect(doc.lastRefreshed, isNull);
      expect(doc.contextualRetrievalEnabled, isFalse);
    });

    test('parses refresh timestamp when present', () {
      final doc = Document.fromJson(<String, dynamic>{
        'id': 'doc-3',
        'title': 'Refresh test',
        'file_path': '/tmp/file.md',
        'format': 'markdown',
        'ingested_at': 1000,
        'last_refreshed': 2000,
      });

      expect(doc.lastRefreshed, DateTime.fromMillisecondsSinceEpoch(2000));
    });
  });

  group('Document.toJson -', () {
    test('serializes every persisted field', () {
      final ingestedAt = DateTime.fromMillisecondsSinceEpoch(1700);
      final refreshedAt = DateTime.fromMillisecondsSinceEpoch(2700);
      final doc = Document(
        id: 'doc-2',
        title: 'Quarterly Report',
        filePath: '/docs/report.md',
        format: DocumentFormat.markdown,
        chunkCount: 7,
        totalCharacters: 999,
        contentHash: 'abc123',
        ingestedAt: ingestedAt,
        status: IngestionStatus.error,
        lastRefreshed: refreshedAt,
        contextualRetrievalEnabled: true,
        embeddingModelId: 'embedding-model',
        errorMessage: 'parse failed',
      );

      expect(doc.toJson(), {
        'id': 'doc-2',
        'title': 'Quarterly Report',
        'file_path': '/docs/report.md',
        'format': 'markdown',
        'chunk_count': 7,
        'total_characters': 999,
        'content_hash': 'abc123',
        'ingested_at': ingestedAt.millisecondsSinceEpoch,
        'status': 'error',
        'last_refreshed': refreshedAt.millisecondsSinceEpoch,
        'contextual_retrieval': 1,
        'embedding_model_id': 'embedding-model',
        'error_message': 'parse failed',
      });
    });
  });
}
