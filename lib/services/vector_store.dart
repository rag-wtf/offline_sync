import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
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
    double semanticWeight = 0.7,
  }) async {
    // 1. Fetch candidates (Keyword Search)
    final keywordResults = _hasFts5
        ? _fts5Search(query, limit: 100) // Increase candidate pool
        : _fallbackKeywordSearch(query, limit: 100);

    // 2. Compute Semantic Search (using Candidates from FTS5 if possible,
    // or all if small)
    // For simplicity, we'll fetch top N candidates from the database or all
    // if total count is small.
    // Here we'll take top 100 from FTS5 and maybe some random/all others
    // if needed, but 100 is usually enough for hybrid.
    // If FTS5 is not available, we have to load more.

    final semanticResults = await _semanticSearchAsync(
      queryEmbedding,
      limit: limit * 2,
    );

    return _mergeResults(
      semanticResults,
      keywordResults,
      semanticWeight: semanticWeight,
      limit: limit,
    );
  }

  Future<List<SearchResult>> _semanticSearchAsync(
    List<double> embedding, {
    required int limit,
  }) async {
    // Fetch all embeddings and IDs from DB
    final rows = _db!.select(
      'SELECT id, content, embedding, metadata FROM vectors',
    );

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

  List<SearchResult> _fts5Search(String query, {required int limit}) {
    final sanitized = _sanitizeFtsQuery(query);

    try {
      final results = _db!.select(
        '''
        SELECT v.*, bm25(vectors_fts) as score
        FROM vectors_fts
        JOIN vectors v ON vectors_fts.rowid = v.rowid
        WHERE vectors_fts MATCH ?
        ORDER BY score
        LIMIT ?
      ''',
        [sanitized, limit],
      );

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
      return _fallbackKeywordSearch(query, limit: limit);
    }
  }

  List<SearchResult> _fallbackKeywordSearch(
    String query, {
    required int limit,
  }) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2);
    if (words.isEmpty) return [];

    final conditions = words
        .map((w) => "LOWER(content) LIKE '%' || ? || '%'")
        .join(' OR ');
    final results = _db!.select(
      'SELECT * FROM vectors WHERE $conditions LIMIT ?',
      [...words, limit],
    );

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

  String _sanitizeFtsQuery(String query) {
    return query.replaceAll('"', '""').replaceAll('*', '').replaceAll('-', ' ');
  }

  /// Merge results using Reciprocal Rank Fusion (RRF)
  /// RRF is the industry standard for hybrid search as it handles
  /// incompatible score scales (BM25 vs cosine similarity) correctly
  List<SearchResult> _mergeResults(
    List<SearchResult> semantic,
    List<SearchResult> keyword, {
    required double semanticWeight,
    required int limit,
  }) {
    const k = 60.0; // RRF constant
    final scores = <String, double>{};
    final items = <String, SearchResult>{};

    // Calculate RRF scores based on rank position
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

    // Sort by RRF score and return top results
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

/// Isolate function for calculating similarities
List<SearchResult> _calculateSimilarities(Map<String, dynamic> params) {
  final queryEmbedding = params['queryEmbedding'] as List<double>;
  final data = params['data'] as List<Map<String, dynamic>>;
  final limit = params['limit'] as int;

  final scored = data.map((item) {
    final storedEmbeddingJson = item['embedding'] as String;
    final storedEmbedding = (jsonDecode(storedEmbeddingJson) as List)
        .map((e) => (e as num).toDouble())
        .toList();

    // Cosine similarity
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
