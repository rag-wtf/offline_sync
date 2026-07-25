/// Benchmark test script.
// ignore_for_file: avoid_print, document_ignores

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.openInMemory()
    ..execute('''
    CREATE TABLE vectors (
      id TEXT PRIMARY KEY,
      document_id TEXT,
      content TEXT,
      embedding TEXT,
      metadata TEXT,
      created_at INTEGER
    )
  ''');

  final items = List.generate(
    1000,
    (i) => {
      'id': 'id_$i',
      'documentId': 'doc_$i',
      'content': 'content $i',
      'embedding': List.generate(1536, (j) => j * 0.1),
      'metadata': {'key': 'value $i', 'index': i},
    },
  );

  // Warmup
  _insertUnoptimized(db, items.take(10).toList());
  _insertOptimized(db, items.take(10).toList());

  db.execute('DELETE FROM vectors');

  final watch1 = Stopwatch()..start();
  _insertUnoptimized(db, items);
  watch1.stop();
  print('Unoptimized: ${watch1.elapsedMilliseconds} ms');

  db.execute('DELETE FROM vectors');

  final watch2 = Stopwatch()..start();
  _insertOptimized(db, items);
  watch2.stop();
  print('Optimized: ${watch2.elapsedMilliseconds} ms');
}

void _insertUnoptimized(Database db, List<Map<String, dynamic>> items) {
  db.execute('BEGIN TRANSACTION');
  final stmt = db.prepare('''
    INSERT OR REPLACE INTO vectors
    (id, document_id, content, embedding, metadata, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  ''');

  for (final item in items) {
    stmt.execute([
      item['id'],
      item['documentId'],
      item['content'],
      jsonEncode(item['embedding']),
      if (item['metadata'] != null) jsonEncode(item['metadata']) else null,
      DateTime.now().millisecondsSinceEpoch,
    ]);
  }

  stmt.close();
  db.execute('COMMIT');
}

void _insertOptimized(Database db, List<Map<String, dynamic>> items) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final encodedItems = items
      .map(
        (item) => [
          item['id'],
          item['documentId'],
          item['content'],
          jsonEncode(item['embedding']),
          if (item['metadata'] != null) jsonEncode(item['metadata']) else null,
          now,
        ],
      )
      .toList();

  db.execute('BEGIN TRANSACTION');
  final stmt = db.prepare('''
    INSERT OR REPLACE INTO vectors
    (id, document_id, content, embedding, metadata, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  ''');

  encodedItems.forEach(stmt.execute);

  stmt.close();
  db.execute('COMMIT');
}
