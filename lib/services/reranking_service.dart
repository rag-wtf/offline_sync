import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';

/// Service for LLM-based relevance reranking of search results
class RerankingService {
  InferenceModel? _inferenceModel;

  /// Rerank chunks by generating relevance scores using LLM
  Future<List<SearchResult>> rerank(
    String query,
    List<SearchResult> candidates, {
    int topK = 5,
  }) async {
    if (candidates.isEmpty) return candidates;

    await _ensureInferenceModel();

    final scoredResults = <_ScoredResult>[];

    // Score each candidate chunk
    for (var i = 0; i < candidates.length && i < topK; i++) {
      final candidate = candidates[i];
      final score = await _scoreRelevance(query, candidate.content);
      scoredResults.add(_ScoredResult(result: candidate, score: score));
    }

    // Sort by relevance score (highest first)
    scoredResults.sort((a, b) => b.score.compareTo(a.score));

    // Return reranked results
    return scoredResults
        .map(
          (scored) => SearchResult(
            id: scored.result.id,
            content: scored.result.content,
            score: scored.score,
            metadata: scored.result.metadata,
          ),
        )
        .toList();
  }

  /// Score the relevance of a document chunk to a query (scale 0-10)
  Future<double> _scoreRelevance(String query, String content) async {
    final prompt =
        '''
Rate the relevance of the following document to the query on a scale of 0-10.
Return ONLY the numeric score, nothing else.

Query: $query

Document: ${content.length > 500 ? '${content.substring(0, 500)}...' : content}

Relevance score:''';

    try {
      final chat = await _inferenceModel!.createChat(temperature: 0.1);
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
      final scoreText = response.toString().trim();
      final score = double.tryParse(
        scoreText.split('\n').first.replaceAll(RegExp('[^0-9.]'), ''),
      );

      return (score ?? 5.0).clamp(0.0, 10.0);
    } on Exception catch (e) {
      debugPrint('[RerankingService] Error scoring relevance: $e');
      // Return neutral score on error
      return 5.0;
    }
  }

  Future<void> _ensureInferenceModel() async {
    if (_inferenceModel != null) return;

    try {
      final settings = locator<RagSettingsService>();
      final userMaxTokens = settings.maxTokens;

      final maxTokens =
          userMaxTokens ??
          ModelConfig.allModels
              .firstWhere(
                (m) => m.type == AppModelType.inference,
                orElse: () => InferenceModels.gemma3_270M,
              )
              .maxTokens;

      _inferenceModel = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
      );
    } catch (e) {
      throw Exception(
        'Failed to get active inference model for reranking: $e',
      );
    }

    if (_inferenceModel == null) {
      throw Exception('No active inference model found for reranking');
    }
  }
}

class _ScoredResult {
  _ScoredResult({required this.result, required this.score});
  final SearchResult result;
  final double score;
}
