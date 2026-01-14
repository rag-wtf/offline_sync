import 'dart:convert';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:sqlite3/common.dart';

/// Repository for persisting chat messages to SQLite
class ChatRepository {
  ChatRepository();

  final VectorStore _vectorStore = locator<VectorStore>();

  CommonDatabase get db {
    final database = _vectorStore.db;
    if (database == null) {
      throw StateError(
        'Database not initialized. Call VectorStore.initialize() first.',
      );
    }
    return database;
  }

  /// Initialize the repository
  /// Note: The chat_messages table is created by VectorStore._onCreate()
  void initialize() {
    // Table creation is handled by VectorStore
    // This method is kept for future initialization needs
  }

  /// Save a chat message
  Future<void> saveMessage(ChatMessage message) async {
    final stmt = db.prepare('''
      INSERT INTO chat_messages (content, is_user, timestamp, sources, metrics)
      VALUES (?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        message.content,
        if (message.isUser) 1 else 0,
        message.timestamp.millisecondsSinceEpoch,
        if (message.sources != null)
          jsonEncode(
            message.sources!
                .map(
                  (s) => {
                    'id': s.id,
                    'content': s.content,
                    'score': s.score,
                    'metadata': s.metadata,
                  },
                )
                .toList(),
          )
        else
          null,
        if (message.metrics != null)
          jsonEncode({
            'embeddingTime': message.metrics!.embeddingTime.inMicroseconds,
            'searchTime': message.metrics!.searchTime.inMicroseconds,
            'generationTime': message.metrics!.generationTime.inMicroseconds,
            'chunksRetrieved': message.metrics!.chunksRetrieved,
          })
        else
          null,
      ]);
    } finally {
      stmt.close();
    }
  }

  /// Load recent messages (default: last 50)
  Future<List<ChatMessage>> loadMessages({int limit = 50}) async {
    final results = db.select(
      '''
      SELECT * FROM chat_messages 
      ORDER BY timestamp DESC 
      LIMIT ?
    ''',
      [limit],
    );

    return results
        .map((row) {
          List<SearchResult>? sources;
          if (row['sources'] != null) {
            final sourcesJson = jsonDecode(row['sources'] as String) as List;
            sources = sourcesJson.map(
              (s) {
                final sourceMap = s as Map<String, dynamic>;
                return SearchResult(
                  id: sourceMap['id'] as String,
                  content: sourceMap['content'] as String,
                  score: sourceMap['score'] as double,
                  metadata: sourceMap['metadata'] as Map<String, dynamic>,
                );
              },
            ).toList();
          }

          RAGMetrics? metrics;
          if (row['metrics'] != null) {
            final metricsJson =
                jsonDecode(row['metrics'] as String) as Map<String, dynamic>;
            metrics = RAGMetrics(
              embeddingTime: Duration(
                microseconds: metricsJson['embeddingTime'] as int,
              ),
              searchTime: Duration(
                microseconds: metricsJson['searchTime'] as int,
              ),
              generationTime: Duration(
                microseconds: metricsJson['generationTime'] as int,
              ),
              chunksRetrieved: metricsJson['chunksRetrieved'] as int,
            );
          }

          return ChatMessage(
            content: row['content'] as String,
            isUser: (row['is_user'] as int) == 1,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              row['timestamp'] as int,
            ),
            sources: sources,
            metrics: metrics,
          );
        })
        .toList()
        .reversed
        .toList(); // Reverse to get chronological order
  }

  /// Clear all chat history
  Future<void> clearHistory() async {
    db.execute('DELETE FROM chat_messages');
  }

  /// Get message count
  Future<int> getMessageCount() async {
    final result = db.select('SELECT COUNT(*) as count FROM chat_messages');
    return result.first['count'] as int;
  }
}
