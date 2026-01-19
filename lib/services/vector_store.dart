import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/rag_constants.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store_path_stub.dart'
    if (dart.library.io) 'package:offline_sync/services/vector_store_path_native.dart'
    as path_helper;
import 'package:sqlite3/common.dart';

// Import platform-specific sqlite3
// On native: global 'sqlite3' available directly
// On web: global 'sqlite3' getter exported from bootstrap_web
import 'package:sqlite3/sqlite3.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart';

class SearchResult {
  SearchResult({
    required this.id,
    required this.content,
    required this.score,
    required this.metadata,
  });
  final String id;
  final String content;
  final double score;
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
  });
  final String id;
  final String documentId;
  final String content;
  final List<double> embedding;
  final Map<String, dynamic>? metadata;
}

class VectorStore {
  CommonDatabase? _db;
  bool _hasFts5 = true;

  /// Expose database for ChatRepository
  CommonDatabase? get db => _db;

  Future<void> initialize() async {
    // On web: use in-memory mode
    // (IndexedDB via bootstrap_web handles persistence)
    // On native: use file-based database
    final dbPath = await path_helper.getDatabasePath('vectors.db');

    _db = sqlite3.open(dbPath);
    _onCreate();

    // Check FTS5 support
    try {
      _db!.select("SELECT fts5('test')");
    } on Exception catch (_) {
      _hasFts5 = false;
    }
  }

  void _onCreate() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS vectors (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding TEXT NOT NULL,
        metadata TEXT,
        created_at INTEGER NOT NULL
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
        metrics TEXT
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
        error_message TEXT
      )
    ''');

    // Index for hash-based duplicate detection (NEW)
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents(content_hash)
    ''');

    if (_hasFts5) {
      try {
        _db!.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS vectors_fts 
          USING fts5(content, content=vectors, content_rowid=rowid)
        ''');

        _db!.execute('''
          CREATE TRIGGER IF NOT EXISTS vectors_ai AFTER INSERT ON vectors BEGIN
            INSERT INTO vectors_fts(rowid, content) VALUES (new.rowid, new.content);
          END
        ''');

        _db!.execute('''
          CREATE TRIGGER IF NOT EXISTS vectors_ad AFTER DELETE ON vectors BEGIN
            INSERT INTO vectors_fts(vectors_fts, rowid, content) 
            VALUES ('delete', old.rowid, old.content);
          END
        ''');
      } on Exception catch (_) {
        _hasFts5 = false;
      }
    }
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
    final keywordResults = _hasFts5
        ? _fts5Search(
            query,
            limit: 100,
            documentIds: documentIds,
          ) // Increase candidate pool
        : _fallbackKeywordSearch(query, limit: 100, documentIds: documentIds);

    // 2. Compute Semantic Search (using Candidates from FTS5 if possible,
    // or all if small)
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
  }) async {
    // Fetch all embeddings and IDs from DB
    // Filter by documentIds if provided
    var sql = 'SELECT id, content, embedding, metadata FROM vectors';
    var params = <Object?>[];

    if (documentIds != null && documentIds.isNotEmpty) {
      final placeholders = List.filled(documentIds.length, '?').join(', ');
      sql += ' WHERE document_id IN ($placeholders)';
      params = documentIds;
    }

    final rows = _db!.select(sql, params);

    // Convert to a format suitable for compute (plain data)
    final data = rows
        .map(
          (Row row) => {
            'id': row['id'],
            'content': row['content'],
            'embedding': row['embedding'] as String,
            'metadata': row['metadata'],
          },
        )
        .toList();

    return compute(_calculateSimilarities, {
      'queryEmbedding': embedding,
      'data': data,
      'limit': limit,
    });
  }

  List<SearchResult> _fts5Search(
    String query, {
    required int limit,
    List<String>? documentIds,
  }) {
    final sanitized = _sanitizeFtsQuery(query);

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
            (Row row) => SearchResult(
              id: row['id'] as String,
              content: row['content'] as String,
              score: -(row['score'] as double),
              metadata:
                  jsonDecode(row['metadata'] as String? ?? '{}')
                      as Map<String, dynamic>,
            ),
          )
          .toList();
    } on Exception catch (_) {
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
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2);
    if (words.isEmpty) return [];

    // Sanitize and limit search terms to prevent SQL injection
    final sanitizedWords = words
        .take(10) // Limit to 10 search terms max
        .map((w) => w.replaceAll(RegExp('[%_]'), '')) // Remove LIKE wildcards
        .where((w) => w.isNotEmpty)
        .toList();

    if (sanitizedWords.isEmpty) return [];

    final conditions = sanitizedWords
        .map((w) => "LOWER(content) LIKE '%' || ? || '%'")
        .join(' OR ');

    var sql = 'SELECT * FROM vectors WHERE ($conditions)';
    final params = <Object?>[...sanitizedWords];

    if (documentIds != null && documentIds.isNotEmpty) {
      final placeholders = List.filled(documentIds.length, '?').join(', ');
      sql += ' AND document_id IN ($placeholders)';
      params.addAll(documentIds);
    }

    sql += ' LIMIT ?';
    params.add(limit);

    final results = _db!.select(sql, params);

    return results
        .map(
          (Row row) => SearchResult(
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
  }) {
    _db!.prepare('''
INSERT OR REPLACE INTO vectors 
         (id, document_id, content, embedding, metadata, created_at) 
         VALUES (?, ?, ?, ?, ?, ?)
''')
      ..execute([
        id,
        documentId,
        content,
        jsonEncode(embedding),
        if (metadata != null) jsonEncode(metadata) else null,
        DateTime.now().millisecondsSinceEpoch,
      ])
      ..close();
  }

  /// Batch insert embeddings within a single transaction for better performance
  void insertEmbeddingsBatch(List<EmbeddingData> items) {
    if (items.isEmpty) return;

    _db!.execute('BEGIN TRANSACTION');
    try {
      final stmt = _db!.prepare('''
        INSERT OR REPLACE INTO vectors 
        (id, document_id, content, embedding, metadata, created_at) 
        VALUES (?, ?, ?, ?, ?, ?)
      ''');

      for (final item in items) {
        stmt.execute([
          item.id,
          item.documentId,
          item.content,
          jsonEncode(item.embedding),
          if (item.metadata != null) jsonEncode(item.metadata) else null,
          DateTime.now().millisecondsSinceEpoch,
        ]);
      }

      stmt.close();
      _db!.execute('COMMIT');
    } catch (e) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  // --- Document Management Methods (NEW) ---

  void insertDocument(Document doc) {
    _db!.prepare('''
      INSERT OR REPLACE INTO documents (
        id, title, file_path, format, chunk_count, total_characters, 
        content_hash, ingested_at, last_refreshed, status, 
        contextual_retrieval, error_message
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''')
      ..execute([
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
        doc.errorMessage,
      ])
      ..close();
  }

  void updateDocument(Document doc) {
    insertDocument(doc); // REPLACE covers update since ID is primary key
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
      'SELECT * FROM vectors WHERE document_id = ? ORDER BY id ASC',
      [documentId],
    );

    return results.map((row) {
      return EmbeddingData(
        id: row['id'] as String,
        documentId: row['document_id'] as String,
        content: row['content'] as String,
        embedding: (jsonDecode(row['embedding'] as String) as List)
            .cast<double>(),
        metadata: row['metadata'] != null
            ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
            : {},
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
    } catch (e) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Optimize database size and performance
  void optimizeDatabase() {
    _db!.execute('VACUUM');
  }

  // -----------------------------------------

  String _sanitizeFtsQuery(String query) {
    return query
        .replaceAll(RegExp(r'["\*\-\(\)\^\:]'), ' ')
        .replaceAll(
          RegExp(r'\b(OR|AND|NOT|NEAR)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

  void close() {
    _db?.close();
    _db = null;
  }
}

/// Isolate function for calculating similarities(must be top-level)
List<SearchResult> _calculateSimilarities(Map<String, dynamic> params) {
  final queryEmbedding = params['queryEmbedding'] as List<double>;
  final data = params['data'] as List<Map<String, dynamic>>;
  final limit = params['limit'] as int;

  final scored = data.map((item) {
    final storedEmbeddingJson = item['embedding'] as String;
    final storedEmbedding = (jsonDecode(storedEmbeddingJson) as List)
        .map((e) => (e as num).toDouble())
        .toList();

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

    return SearchResult(
      id: item['id'] as String,
      content: item['content'] as String,
      score: score,
      metadata:
          jsonDecode(item['metadata'] as String? ?? '{}')
              as Map<String, dynamic>,
    );
  }).toList();

  return (scored..sort((a, b) => b.score.compareTo(a.score)))
      .take(limit)
      .toList();
}
