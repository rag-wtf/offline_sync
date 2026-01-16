import 'package:offline_sync/services/document_parser_service.dart';

enum IngestionStatus { pending, processing, complete, error }

class Document {
  const Document({
    required this.id,
    required this.title,
    required this.filePath,
    required this.format,
    required this.chunkCount,
    required this.totalCharacters,
    required this.contentHash,
    required this.ingestedAt,
    this.status = IngestionStatus.pending,
    this.lastRefreshed,
    this.contextualRetrievalEnabled = false,
    this.errorMessage,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      title: json['title'] as String,
      filePath: json['file_path'] as String,
      format: DocumentFormat.values.firstWhere(
        (e) => e.name == json['format'],
        orElse: () => DocumentFormat.unknown,
      ),
      chunkCount: json['chunk_count'] as int,
      totalCharacters: json['total_characters'] as int,
      contentHash: json['content_hash'] as String,
      ingestedAt: DateTime.fromMillisecondsSinceEpoch(
        json['ingested_at'] as int,
      ),
      status: IngestionStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'complete'),
        orElse: () => IngestionStatus.complete,
      ),
      lastRefreshed: json['last_refreshed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_refreshed'] as int)
          : null,
      contextualRetrievalEnabled: (json['contextual_retrieval'] as int?) == 1,
      errorMessage: json['error_message'] as String?,
    );
  }

  final String id;
  final String title;
  final String filePath;
  final DocumentFormat format;
  final int chunkCount;
  final int totalCharacters;
  final String contentHash;
  final DateTime ingestedAt;
  final DateTime? lastRefreshed;
  final IngestionStatus status;
  final bool contextualRetrievalEnabled;
  final String? errorMessage;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'file_path': filePath,
      'format': format.name,
      'chunk_count': chunkCount,
      'total_characters': totalCharacters,
      'content_hash': contentHash,
      'ingested_at': ingestedAt.millisecondsSinceEpoch,
      'status': status.name,
      'last_refreshed': lastRefreshed?.millisecondsSinceEpoch,
      'contextual_retrieval': contextualRetrievalEnabled ? 1 : 0,
      'error_message': errorMessage,
    };
  }
}
