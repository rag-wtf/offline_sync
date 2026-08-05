import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/rag_constants.dart';
import 'package:offline_sync/services/vector_store.dart';

/// Service for LLM-based relevance reranking of search results
class RerankingService {
  final InferenceModelProvider _inferenceModelProvider =
      locator<InferenceModelProvider>();

  /// Rerank chunks by generating relevance scores using LLM
  Future<List<SearchResult>> rerank(
    String query,
    List<SearchResult> candidates, {
    int topK = 5,
  }) async {
    if (candidates.isEmpty) return candidates;

    try {
      final inferenceModel = await _inferenceModelProvider.getModel();
      final candidatesToScore = candidates.take(topK).toList();

      // Bound concurrency by scoring candidates in batches of 5
      final scoredResults = <_ScoredResult>[];
      const batchSize = 5;
      for (var i = 0; i < candidatesToScore.length; i += batchSize) {
        final batch = candidatesToScore.skip(i).take(batchSize);
        final batchScored = await Future.wait(
          batch.map((candidate) async {
            final score = await _scoreRelevance(
              inferenceModel,
              query,
              candidate.content,
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: () => 5.0,
            );
            return _ScoredResult(result: candidate, score: score);
          }),
        );
        scoredResults.addAll(batchScored);
      }

      // Sort by relevance score (highest first)
      final sortedResults = List<_ScoredResult>.from(scoredResults)
        ..sort((a, b) => b.score.compareTo(a.score));

      // Return reranked results
      return sortedResults
          .map(
            (scored) => SearchResult(
              id: scored.result.id,
              content: scored.result.content,
              score: scored.score,
              metadata: scored.result.metadata,
            ),
          )
          .toList();
    } on Exception catch (e, stack) {
      LoggingService.error(
        'Error reranking results',
        name: 'RerankingService',
        error: e,
        stackTrace: stack,
      );
      // Return original candidates on error
      return candidates;
    }
  }

  /// Score the relevance of a document chunk to a query (scale 0-10)
  Future<double> _scoreRelevance(
    InferenceModel inferenceModel,
    String query,
    String content,
  ) async {
    const maxChars = RagConstants.maxCharsForReranking;
    final truncatedContent = content.length > maxChars
        ? '${content.substring(0, maxChars)}...'
        : content;

    final prompt = '''
Rate the relevance of the following document to the query on a scale of 0-10.
Return ONLY the numeric score, nothing else.

Query: $query

Document: $truncatedContent

Relevance score:''';

    try {
      final chat = await inferenceModel.createChat(temperature: 0.1);
      await chat.initSession();
      await chat.addQuery(Message(text: prompt, isUser: true));

      final response = StringBuffer();
      final stream = chat.generateChatResponseAsync();
      await for (final modelResponse in stream) {
        if (modelResponse is TextResponse) {
          response.write(modelResponse.token);
        }
      }

      // Parse score from response
      final scoreText = response.toString().trim().split('\n').first;
      final match = RegExp(r'\d+(\.\d+)?').firstMatch(scoreText);
      final score = match != null ? double.tryParse(match.group(0)!) : null;

      return (score ?? 5.0).clamp(0.0, 10.0);
    } on Exception catch (e, stack) {
      LoggingService.error(
        'Error scoring relevance',
        name: 'RerankingService',
        error: e,
        stackTrace: stack,
      );
      // Return neutral score on error
      return 5.0;
    }
  }
}

class _ScoredResult {
  _ScoredResult({required this.result, required this.score});
  final SearchResult result;
  final double score;
}
