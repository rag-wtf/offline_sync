import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/rag_constants.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store_path_stub.dart'
    if (dart.library.io) 'package:offline_sync/services/vector_store_path_native.dart'
    as path_helper;
import 'package:offline_sync/services/vector_store_persistence_stub.dart'
    if (dart.library.html) 'package:offline_sync/services/vector_store_persistence_web.dart'
    as persistence;
import 'package:sqlite3/common.dart';

// Import platform-specific sqlite3
// On native: global 'sqlite3' available directly
// On web: global 'sqlite3' getter exported from bootstrap_web
import 'package:sqlite3/sqlite3.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart';

/// Result of a vector search operation
class SearchResult {
  SearchResult({
    required this.id,
    required this.content,
    required this.score,
    required this.metadata,
  });

  /// Unique identifier for the chunk
  final String id;

  /// Text content of the chunk
  final String content;

  /// Combined relevance score (semantic + keyword)
  final double score;

  /// Metadata associated with the chunk (document ID, title, etc.)
  final Map<String, dynamic> metadata;

  // Typed getters for source attribution
  String? get documentId => metadata['documentId'] as String?;
  String? get documentTitle => metadata['documentTitle'] as String?;
  String? get documentPath => metadata['documentPath'] as String?;
  int? get chunkIndex => metadata['seq'] as int?;
  // You might add totalChunks here if you inject it into metadata
}

/// Data class for batch embedding insertions
class EmbeddingData {
  EmbeddingData({
    required this.id,
    required this.documentId,
    required this.content,
    required this.embedding,
    this.metadata,
    this.embeddingModelId,
  });
  final String id;
  final String documentId;
  final String content;
  final List<double> embedding;
  final Map<String, dynamic>? metadata;
  final String? embeddingModelId;
}

typedef PersistenceOperation = Future<void> Function();

class VectorStore {
  VectorStore({
    @visibleForTesting PersistenceOperation? flushDatabase,
    @visibleForTesting PersistenceOperation? closeDatabase,
  }) : _flushDatabase = flushDatabase ?? persistence.flushDatabase,
       _closeDatabase = closeDatabase ?? persistence.closeDatabase;

  // Pre-compiled Regular Expressions for performance optimization
  static final _ftsWordRegex = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

  /// Current on-disk schema version. Bump when the schema changes and add a
  /// matching branch in [_migrate].
  static const int schemaVersion = 7;

  CommonDatabase? _db;
  bool _hasFts5 = true;
  Future<void> _persistenceLane = Future<void>.value();
  Future<void> _latestPersistenceFlush = Future<void>.value();
  final PersistenceOperation _flushDatabase;
  final PersistenceOperation _closeDatabase;

  /// Expose database for ChatRepository
  CommonDatabase? get db => _db;

  /// Initializes the SQLite database and creates tables if they don't exist
  Future<void> initialize() async {
    // On web: use in-memory mode
    // (IndexedDB via bootstrap_web handles persistence)
    // On native: use file-based database
    final dbPath = await path_helper.getDatabasePath('vectors.db');

    _db = sqlite3.open(dbPath);
    _db!.execute('PRAGMA recursive_triggers = ON;');
    _onCreate();

    final currentVersion =
        _db!.select('PRAGMA user_version').first.values.first as int? ?? 0;
    if (currentVersion < schemaVersion) {
      _migrate(currentVersion);
      _db!.execute('PRAGMA user_version = $schemaVersion');
    }

    // Check FTS5 support
    try {
      _db!.select("SELECT fts5('test')");
      _createFtsObjects();
      // coverage:ignore-start
    } on Exception catch (_) {
      _hasFts5 = false;
    }
    // coverage:ignore-end
  }

  void _onCreate() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS vectors (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding TEXT NOT NULL,
        metadata TEXT,
        created_at INTEGER NOT NULL,
        embedding_model_id TEXT,
        embedding_encoding TEXT NOT NULL DEFAULT 'float32',
        embedding_dimension INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create index on document_id for efficient document-based queries
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_vectors_doc_id ON vectors(document_id)
    ''');

    // Chat messages table for persistence
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        sources TEXT,
        metrics TEXT,
        is_failed INTEGER NOT NULL DEFAULT 0,
        is_pending INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create index on timestamp for efficient chronological queries
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_timestamp ON chat_messages(timestamp)
    ''');

    // Documents table for management (NEW)
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS documents (
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
        embedding_model_id TEXT,
        error_message TEXT
      )
    ''');
  }

  void _createFtsObjects() {
    try {
      _db!.execute('DROP TRIGGER IF EXISTS vectors_ad');
      _db!.execute('DROP TRIGGER IF EXISTS vectors_bd');

      _db!.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS vectors_fts 
        USING fts5(content, content=vectors, content_rowid=rowid)
      ''');

      _db!.execute('DROP TRIGGER IF EXISTS vectors_ad');

      _db!.execute('''
        CREATE TRIGGER IF NOT EXISTS vectors_ai AFTER INSERT ON vectors BEGIN
          INSERT OR IGNORE INTO vectors_fts(rowid, content) VALUES (new.rowid, new.content);
        END
      ''');

      _db!.execute('''
        CREATE TRIGGER IF NOT EXISTS vectors_bd BEFORE DELETE ON vectors BEGIN
          INSERT OR IGNORE INTO vectors_fts(vectors_fts, rowid, content) 
          VALUES ('delete', old.rowid, old.content);
        END
      ''');
      // coverage:ignore-start
    } on Exception catch (_) {
      _hasFts5 = false;
    }
    // coverage:ignore-end
  }

  /// Applies ordered, gated migrations from [fromVersion] to [schemaVersion].
  void _migrate(int fromVersion) {
    // v0 -> v1: baseline. Tables already created by _onCreate().
    if (fromVersion < 2) {
      _db!.execute('''
        DELETE FROM vectors WHERE document_id IN (
          SELECT id FROM documents WHERE rowid NOT IN (
            SELECT MIN(rowid) FROM documents GROUP BY content_hash
          )
        )
      ''');
      _db!.execute('''
        DELETE FROM documents WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM documents GROUP BY content_hash
        )
      ''');
      _db!.execute('DROP INDEX IF EXISTS idx_documents_hash');
      _db!.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_documents_hash
        ON documents(content_hash)
      ''');
    }
    if (fromVersion < 3) {
      try {
        _db!.execute('ALTER TABLE vectors ADD COLUMN embedding_model_id TEXT');
      } on Object catch (_) {}
      _db!.execute(
        'UPDATE vectors SET embedding_model_id = ? '
        'WHERE embedding_model_id IS NULL',
        [_activeEmbeddingModelId],
      );
    }
    if (fromVersion < 4) {
      try {
        _db!.execute(
          'ALTER TABLE vectors ADD COLUMN embedding_encoding TEXT '
          "NOT NULL DEFAULT 'float32'",
        );
      } on Object catch (_) {}
      try {
        _db!.execute(
          'ALTER TABLE vectors ADD COLUMN embedding_dimension INTEGER '
          'NOT NULL DEFAULT 0',
        );
      } on Object catch (_) {}

      final rows = _db!.select('SELECT rowid, embedding FROM vectors');
      for (final row in rows) {
        final encoded = row['embedding'] as String;
        String encoding;
        var dimension = 0;
        if (encoded.startsWith('[')) {
          try {
            final decoded = jsonDecode(encoded);
            if (decoded is! List || decoded.isEmpty) {
              throw const FormatException('Invalid legacy JSON embedding');
            }
            for (final value in decoded) {
              if (value is! num) {
                throw const FormatException(
                  'Legacy JSON embedding contains a non-number',
                );
              }
            }
            encoding = 'json';
            dimension = decoded.length;
          } on Object catch (_) {
            encoding = 'unknown';
          }
        } else {
          // Legacy base64 rows have no trustworthy encoding metadata. Do
          // not guess Float32 from a byte length that may be Float64.
          encoding = 'unknown';
        }
        _db!.execute(
          'UPDATE vectors SET embedding_encoding = ?, '
          'embedding_dimension = ? WHERE rowid = ?',
          [
            encoding,
            dimension,
            row['rowid'],
          ],
        );
      }
    }
    if (fromVersion < 5) {
      try {
        _db!.execute(
          'ALTER TABLE chat_messages ADD COLUMN is_failed INTEGER '
          'NOT NULL DEFAULT 0',
        );
      } on Object catch (_) {}
    }
    if (fromVersion < 6) {
      try {
        _db!.execute(
          'ALTER TABLE chat_messages ADD COLUMN is_pending INTEGER '
          'NOT NULL DEFAULT 0',
        );
      } on Object catch (_) {}
    }
    if (fromVersion < 7) {
      try {
        _db!.execute(
          'ALTER TABLE documents ADD COLUMN embedding_model_id TEXT',
        );
      } on Object catch (_) {}
    }

    // v3 databases may already exist with legacy NULL model identifiers.
    // Keep those rows in the active embedder's corpus instead of mixing them
    // into searches implicitly.
    _db!.execute(
      'UPDATE vectors SET embedding_model_id = ? '
      'WHERE embedding_model_id IS NULL',
      [_activeEmbeddingModelId],
    );
  }

  String get _activeEmbeddingModelId {
    final configured = locator.isRegistered<RagSettingsService>()
        ? locator<RagSettingsService>().activeEmbeddingModelId
        : null;
    return configured ?? EmbeddingModels.gecko64.id;
  }

  Future<List<SearchResult>> hybridSearch(
    String query,
    List<double> queryEmbedding, {
    int limit = 5,
    double? semanticWeight,
    List<String>? documentIds,
  }) async {
    // Get semantic weight from settings if not provided
    final settingsService = locator<RagSettingsService>();
    final weight = semanticWeight ?? settingsService.semanticWeight;

    // 1. Fetch candidates (Keyword Search)
    // coverage:ignore-start
    final keywordResults = _hasFts5
        ? _fts5Search(
            query,
            limit: RagConstants.hybridSearchCandidatePoolSize,
            documentIds: documentIds,
          ) // Increase candidate pool
        : _fallbackKeywordSearch(
            query,
            limit: RagConstants.hybridSearchCandidatePoolSize,
            documentIds: documentIds,
          );
    // coverage:ignore-end

    // 2. Compute semantic search over the complete eligible embedding space.
    // Keyword results are blended for ranking only; they never gate recall.
    final semanticResults = await _semanticSearchAsync(
      queryEmbedding,
      limit: limit * 2,
      documentIds: documentIds,
    );

    return mergeResults(
      semanticResults,
      keywordResults,
      semanticWeight: weight,
      limit: limit,
    );
  }

  Future<List<SearchResult>> _semanticSearchAsync(
    List<double> embedding, {
    required int limit,
    List<String>? documentIds,
    String? embeddingModelId,
  }) async {
    final conditions = <String>[];

    final activeModelId = embeddingModelId ?? _activeEmbeddingModelId;
    conditions.add('embedding_model_id = ?');

    const batchSize = 256;
    var lastRowId = 0;
    final bestResults = <SearchResult>[];

    while (true) {
      var sql =
          'SELECT rowid, id, content, embedding, metadata, '
          'embedding_encoding, embedding_dimension FROM vectors';
      final params = <Object?>[activeModelId];
      final batchConditions = <String>[...conditions, 'rowid > ?'];
      params.add(lastRowId);

      if (documentIds != null && documentIds.isNotEmpty) {
        final placeholders = List.filled(documentIds.length, '?').join(', ');
        batchConditions.add('document_id IN ($placeholders)');
        params.addAll(documentIds);
      }

      sql +=
          ' WHERE ${batchConditions.join(' AND ')} '
          'ORDER BY rowid ASC LIMIT ?';
      params.add(batchSize);
      final rows = _db!.select(sql, params);
      if (rows.isEmpty) break;
      lastRowId = rows.last['rowid'] as int;

      final data = rows
          .map(
            (row) => {
              'id': row['id'],
              'content': row['content'],
              'embedding': row['embedding'] as String,
              'encoding': row['embedding_encoding'] as String?,
              'dimension': row['embedding_dimension'] as int?,
              'metadata': row['metadata'],
            },
          )
          .toList();

      bestResults.addAll(
        await compute(_calculateSimilarities, {
          'queryEmbedding': embedding,
          'data': data,
          'limit': limit,
        }),
      );
      final rankedResults = bestResults
        ..sort((a, b) => b.score.compareTo(a.score));
      if (rankedResults.length > limit) {
        rankedResults.removeRange(limit, rankedResults.length);
      }
    }

    return bestResults;
  }

  List<SearchResult> _fts5Search(
    String query, {
    required int limit,
    List<String>? documentIds,
  }) {
    final sanitized = _sanitizeFtsQuery(query);
    if (sanitized.isEmpty) return [];

    try {
      var sql = '''
      SELECT v.*, bm25(vectors_fts) as score
      FROM vectors_fts
      JOIN vectors v ON vectors_fts.rowid = v.rowid
      WHERE vectors_fts MATCH ?
    ''';
      final params = <Object?>[sanitized];

      if (documentIds != null && documentIds.isNotEmpty) {
        final placeholders = List.filled(documentIds.length, '?').join(', ');
        sql += ' AND v.document_id IN ($placeholders)';
        params.addAll(documentIds);
      }

      sql += ' ORDER BY score LIMIT ?';
      params.add(limit);

      final results = _db!.select(sql, params);

      return results
          .map(
            (row) => SearchResult(
              id: row['id'] as String,
              content: row['content'] as String,
              score: -(row['score'] as double),
              metadata:
                  jsonDecode(row['metadata'] as String? ?? '{}')
                      as Map<String, dynamic>,
            ),
          )
          .toList();
    } on Object catch (error) {
      LoggingService.warning(
        'FTS search failed; using keyword fallback: $error',
        name: 'VectorStore',
      );
      return _fallbackKeywordSearch(
        query,
        limit: limit,
        documentIds: documentIds,
      );
    }
  }

  List<SearchResult> _fallbackKeywordSearch(
    String query, {
    required int limit,
    List<String>? documentIds,
  }) {
    LoggingService.warning(
      'Using LIKE keyword fallback for vector search',
      name: 'VectorStore',
    );
    final words = _ftsWordRegex
        .allMatches(query.toLowerCase())
        .map((match) => match.group(0)!)
        .take(10)
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return [];

    final conditions = words
        .map((w) => "LOWER(content) LIKE '%' || ? || '%'")
        .join(' OR ');

    var sql = 'SELECT * FROM vectors WHERE ($conditions)';
    final params = <Object?>[...words];

    if (documentIds != null && documentIds.isNotEmpty) {
      final placeholders = List.filled(documentIds.length, '?').join(', ');
      sql += ' AND document_id IN ($placeholders)';
      params.addAll(documentIds);
    }

    sql += ' ORDER BY created_at DESC, id ASC LIMIT ?';
    params.add(limit);

    final results = _db!.select(sql, params);

    return results
        .map(
          (row) => SearchResult(
            id: row['id'] as String,
            content: row['content'] as String,
            score: 0.5,

            metadata:
                jsonDecode(row['metadata'] as String? ?? '{}')
                    as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  void insertEmbedding({
    required String id,
    required String documentId,
    required String content,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
    String? embeddingModelId,
  }) {
    final stmt = _db!.prepare('''
      INSERT OR REPLACE INTO vectors 
      (id, document_id, content, embedding, metadata, created_at,
       embedding_model_id, embedding_encoding, embedding_dimension)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        id,
        documentId,
        content,
        base64Encode(Float32List.fromList(embedding).buffer.asUint8List()),
        if (metadata != null) jsonEncode(metadata) else null,
        DateTime.now().millisecondsSinceEpoch,
        embeddingModelId ?? _activeEmbeddingModelId,
        'float32',
        embedding.length,
      ]);
    } finally {
      stmt.close();
    }
    _schedulePersistenceFlush();
  }

  /// Batch insert embeddings within a single transaction for better performance
  void insertEmbeddingsBatch(List<EmbeddingData> items) {
    if (items.isEmpty) return;

    _db!.execute('BEGIN TRANSACTION');
    try {
      final stmt = _db!.prepare('''
        INSERT OR REPLACE INTO vectors 
        (id, document_id, content, embedding, metadata, created_at,
         embedding_model_id, embedding_encoding, embedding_dimension)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      try {
        for (final item in items) {
          stmt.execute([
            item.id,
            item.documentId,
            item.content,
            base64Encode(
              Float32List.fromList(item.embedding).buffer.asUint8List(),
            ),
            if (item.metadata != null) jsonEncode(item.metadata) else null,
            DateTime.now().millisecondsSinceEpoch,
            item.embeddingModelId ?? _activeEmbeddingModelId,
            'float32',
            item.embedding.length,
          ]);
        }
      } finally {
        stmt.close();
      }
      _db!.execute('COMMIT');
      _schedulePersistenceFlush();
    } catch (e) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  // --- Document Management Methods (NEW) ---

  void insertDocument(Document doc) {
    final stmt = _db!.prepare('''
      INSERT INTO documents (
        id, title, file_path, format, chunk_count, total_characters, 
        content_hash, ingested_at, last_refreshed, status, 
        contextual_retrieval, embedding_model_id, error_message
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        file_path = excluded.file_path,
        format = excluded.format,
        chunk_count = excluded.chunk_count,
        total_characters = excluded.total_characters,
        content_hash = excluded.content_hash,
        ingested_at = excluded.ingested_at,
        last_refreshed = excluded.last_refreshed,
        status = excluded.status,
        contextual_retrieval = excluded.contextual_retrieval,
        embedding_model_id = excluded.embedding_model_id,
        error_message = excluded.error_message
    ''');
    try {
      stmt.execute([
        doc.id,
        doc.title,
        doc.filePath,
        doc.format.name,
        doc.chunkCount,
        doc.totalCharacters,
        doc.contentHash,
        doc.ingestedAt.millisecondsSinceEpoch,
        doc.lastRefreshed?.millisecondsSinceEpoch,
        doc.status.name,
        if (doc.contextualRetrievalEnabled) 1 else 0,
        doc.embeddingModelId,
        doc.errorMessage,
      ]);
    } finally {
      stmt.close();
    }
    _schedulePersistenceFlush();
  }

  void updateDocument(Document doc) {
    insertDocument(doc);
  }

  /// Renames a document and updates source-attribution metadata atomically.
  void renameDocument(String documentId, String title) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Title cannot be empty');
    }
    _db!.execute('BEGIN TRANSACTION');
    try {
      _db!.execute(
        'UPDATE documents SET title = ? WHERE id = ?',
        [normalizedTitle, documentId],
      );
      final rows = _db!.select(
        'SELECT id, metadata FROM vectors WHERE document_id = ?',
        [documentId],
      );
      for (final row in rows) {
        final metadata = row['metadata'] == null
            ? <String, dynamic>{}
            : jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
        metadata['documentTitle'] = normalizedTitle;
        _db!.execute(
          'UPDATE vectors SET metadata = ? WHERE id = ?',
          [jsonEncode(metadata), row['id']],
        );
      }
      _db!.execute('COMMIT');
      _schedulePersistenceFlush();
    } on Object catch (_) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteDocumentEmbeddings(String id) {
    _db!.execute('BEGIN TRANSACTION');
    try {
      _db!.execute('DELETE FROM vectors WHERE document_id = ?', [id]);
      _db!.execute('COMMIT');
      _schedulePersistenceFlush();
    } on Object catch (_) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  Document? getDocument(String id) {
    final result = _db!.select('SELECT * FROM documents WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Document.fromJson(result.first);
  }

  List<Document> getAllDocuments() {
    final result = _db!.select(
      'SELECT * FROM documents ORDER BY ingested_at DESC',
    );
    return result.map(Document.fromJson).toList();
  }

  Document? findByHash(String hash) {
    final result = _db!.select(
      'SELECT * FROM documents WHERE content_hash = ?',
      [hash],
    );
    if (result.isEmpty) return null;
    return Document.fromJson(result.first);
  }

  List<EmbeddingData> getChunksForDocument(String documentId) {
    final results = _db!.select(
      r'''
      SELECT * FROM vectors 
      WHERE document_id = ? 
      ORDER BY CAST(json_extract(metadata, '$.seq') AS INTEGER) ASC, id ASC
      ''',
      [documentId],
    );

    return results.map((row) {
      return EmbeddingData(
        id: row['id'] as String,
        documentId: row['document_id'] as String,
        content: row['content'] as String,
        embedding: _decodeEmbedding(
          row['embedding'] as String,
          encoding: row['embedding_encoding'] as String,
          dimension: row['embedding_dimension'] as int,
        ),
        metadata: row['metadata'] != null
            ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
            : {},
        embeddingModelId: row['embedding_model_id'] as String?,
      );
    }).toList();
  }

  void deleteDocument(String id) {
    _db!.execute('BEGIN TRANSACTION');
    try {
      // Delete document record
      _db!.execute('DELETE FROM documents WHERE id = ?', [id]);

      // Delete associated vectors
      _db!.execute('DELETE FROM vectors WHERE document_id = ?', [id]);

      _db!.execute('COMMIT');
      _schedulePersistenceFlush();
    } on Object catch (_) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteAllDocuments() {
    _db!.execute('BEGIN TRANSACTION');
    try {
      _db!.execute('DELETE FROM vectors WHERE 1=1');
      _db!.execute('DELETE FROM documents WHERE 1=1');
      _db!.execute('COMMIT');
      _schedulePersistenceFlush();
    } on Object catch (_) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Optimize database size and performance
  void optimizeDatabase() {
    _db!.execute('VACUUM');
    _schedulePersistenceFlush();
  }

  // -----------------------------------------

  String _sanitizeFtsQuery(String query) {
    return _ftsWordRegex
        .allMatches(query)
        .map((match) => '"${match.group(0)!.replaceAll('"', '""')}"')
        .join(' ');
  }

  @visibleForTesting
  List<SearchResult> mergeResults(
    List<SearchResult> semantic,
    List<SearchResult> keyword, {
    required double semanticWeight,
    required int limit,
  }) {
    const k = RagConstants.rrfConstant;
    final scores = <String, double>{};
    final items = <String, SearchResult>{};

    for (var i = 0; i < semantic.length; i++) {
      final id = semantic[i].id;
      scores[id] = (scores[id] ?? 0) + semanticWeight / (k + i + 1);
      items[id] = semantic[i];
    }

    final keywordWeight = 1.0 - semanticWeight;
    for (var i = 0; i < keyword.length; i++) {
      final id = keyword[i].id;
      scores[id] = (scores[id] ?? 0) + keywordWeight / (k + i + 1);
      items[id] ??= keyword[i];
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(limit)
        .map(
          (e) => SearchResult(
            id: e.key,
            content: items[e.key]!.content,
            score: e.value,
            metadata: items[e.key]!.metadata,
          ),
        )
        .toList();
  }

  Future<void> close() async {
    // Await all writes queued before shutdown before closing SQLite and its
    // platform VFS. Native persistence uses a no-op implementation.
    await flush();
    _db?.close();
    _db = null;
    await _closeDatabase();
  }

  /// Flushes platform-backed persistence, if the active database needs it.
  Future<void> flush() => _latestPersistenceFlush;

  void _schedulePersistenceFlush() {
    final next = _persistenceLane.then<void>(
      (_) => _flushDatabase(),
    );
    _persistenceLane = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _latestPersistenceFlush = next;
  }
}

List<double> _decodeEmbedding(
  String encodedString, {
  required String encoding,
  required int dimension,
}) {
  if (encodedString.startsWith('[')) {
    if (encoding != 'json') return [];
    final values = (jsonDecode(encodedString) as List)
        .map((e) => (e as num).toDouble())
        .toList();
    if (values.length != dimension) return [];
    return values;
  }
  if (dimension <= 0) return [];
  final bytes = base64Decode(encodedString);
  if (encoding == 'float64') {
    if (bytes.lengthInBytes != dimension * 8) {
      return [];
    }
    return Float64List.view(bytes.buffer).toList();
  }
  if (encoding == 'float32' && bytes.lengthInBytes == dimension * 4) {
    return Float32List.view(bytes.buffer).toList();
  }
  return [];
}

/// Isolate function for calculating similarities(must be top-level)
List<SearchResult> _calculateSimilarities(Map<String, dynamic> params) {
  final queryEmbedding = params['queryEmbedding'] as List<double>;
  final data = params['data'] as List<Map<String, dynamic>>;
  final limit = params['limit'] as int;

  final scored = <SearchResult>[];
  for (final item in data) {
    final storedEmbeddingJson = item['embedding'] as String;
    final storedDimension = item['dimension'] as int?;
    final encoding = item['encoding'] as String?;
    if (encoding == null || storedDimension == null || storedDimension <= 0) {
      continue;
    }
    final storedEmbedding = _decodeEmbedding(
      storedEmbeddingJson,
      encoding: encoding,
      dimension: storedDimension,
    );

    if (storedEmbedding.length != queryEmbedding.length) {
      continue;
    }

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < queryEmbedding.length; i++) {
      dotProduct += queryEmbedding[i] * storedEmbedding[i];
      normA += queryEmbedding[i] * queryEmbedding[i];
      normB += storedEmbedding[i] * storedEmbedding[i];
    }
    final divisor = sqrt(normA) * sqrt(normB);
    final score = divisor == 0 ? 0.0 : dotProduct / divisor;

    scored.add(
      SearchResult(
        id: item['id'] as String,
        content: item['content'] as String,
        score: score,
        metadata:
            jsonDecode(item['metadata'] as String? ?? '{}')
                as Map<String, dynamic>,
      ),
    );
  }

  return (scored..sort((a, b) => b.score.compareTo(a.score)))
      .take(limit)
      .toList();
}
