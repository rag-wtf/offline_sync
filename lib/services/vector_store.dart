import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

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

class VectorStore {
  Database? _db;
  bool _hasFts5 = true;

  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, 'vectors.db');

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
        embedding BLOB NOT NULL,
        metadata TEXT,
        created_at INTEGER NOT NULL
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

  List<SearchResult> hybridSearch(
    String query,
    List<double> queryEmbedding, {
    int limit = 5,
    double semanticWeight = 0.7,
  }) {
    final semanticResults = _semanticSearch(queryEmbedding, limit: limit * 2);
    final keywordResults = _hasFts5
        ? _fts5Search(query, limit: limit * 2)
        : _fallbackKeywordSearch(query, limit: limit * 2);

    return _mergeResults(
      semanticResults,
      keywordResults,
      semanticWeight: semanticWeight,
      limit: limit,
    );
  }

  List<SearchResult> _semanticSearch(
    List<double> embedding, {
    required int limit,
  }) {
    final rows = _db!.select('SELECT * FROM vectors');

    final scored = rows.map((row) {
      final storedEmbedding = _decodeEmbedding(row['embedding'] as Uint8List);
      final score = _cosineSimilarity(embedding, storedEmbedding);
      return SearchResult(
        id: row['id'] as String,
        content: row['content'] as String,
        score: score,
        metadata:
            jsonDecode(row['metadata'] as String? ?? '{}')
                as Map<String, dynamic>,
      );
    }).toList();

    return scored
      ..sort((a, b) => b.score.compareTo(a.score))
      ..take(limit).toList();
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
  }) {
    final embeddingBytes = _encodeEmbedding(embedding);

    _db!.prepare('''
INSERT OR REPLACE INTO vectors 
         (id, document_id, content, embedding, metadata, created_at) 
         VALUES (?, ?, ?, ?, ?, ?)''')
      ..execute([
        id,
        documentId,
        content,
        embeddingBytes,
        if (metadata != null) jsonEncode(metadata) else null,
        DateTime.now().millisecondsSinceEpoch,
      ])
      ..dispose();
  }

  List<double> _decodeEmbedding(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    final embedding = <double>[];
    for (var i = 0; i < bytes.length; i += 4) {
      embedding.add(byteData.getFloat32(i, Endian.little));
    }
    return embedding;
  }

  Uint8List _encodeEmbedding(List<double> embedding) {
    final bytes = Uint8List(embedding.length * 4);
    final byteData = ByteData.sublistView(bytes);
    for (var i = 0; i < embedding.length; i++) {
      byteData.setFloat32(i * 4, embedding[i], Endian.little);
    }
    return bytes;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final divisor = sqrt(normA) * sqrt(normB);
    return divisor == 0 ? 0.0 : dotProduct / divisor;
  }

  String _sanitizeFtsQuery(String query) {
    return query.replaceAll('"', '""').replaceAll('*', '').replaceAll('-', ' ');
  }

  List<SearchResult> _mergeResults(
    List<SearchResult> semantic,
    List<SearchResult> keyword, {
    required double semanticWeight,
    required int limit,
  }) {
    final merged = <String, SearchResult>{};
    final keywordWeight = 1.0 - semanticWeight;

    for (final s in semantic) {
      merged[s.id] = SearchResult(
        id: s.id,
        content: s.content,
        score: s.score * semanticWeight,
        metadata: s.metadata,
      );
    }

    for (final k in keyword) {
      if (merged.containsKey(k.id)) {
        final existing = merged[k.id]!;
        merged[k.id] = SearchResult(
          id: k.id,
          content: k.content,
          score: existing.score + (k.score * keywordWeight),
          metadata: k.metadata,
        );
      } else {
        merged[k.id] = SearchResult(
          id: k.id,
          content: k.content,
          score: k.score * keywordWeight,
          metadata: k.metadata,
        );
      }
    }

    final sorted = merged.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(limit).toList();
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}
