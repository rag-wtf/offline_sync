import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';

/// Service for expanding queries to improve retrieval recall
class QueryExpansionService {
  final EmbeddingService _embeddingService = locator<EmbeddingService>();
  final VectorStore _vectorStore = locator<VectorStore>();

  InferenceModel? _inferenceModel;

  /// Generates 2-3 rephrased variants of the original query
  Future<List<String>> expandQuery(String query) async {
    await _ensureInferenceModel();

    final prompt =
        '''
Rephrase the following query in 2 different ways. 
Keep each variant concise and semantically similar.
Return only the variants, one per line, without numbering or explanations.

Original query: $query

Variants:''';

    try {
      final chat = await _inferenceModel!.createChat(temperature: 0.3);
      await chat.initSession();
      await chat.addQuery(Message(text: prompt, isUser: true));

      final response = StringBuffer();
      final stream = chat.generateChatResponseAsync();
      await for (final modelResponse in stream) {
        if (modelResponse is TextResponse) {
          response.write(modelResponse.token);
        }
      }

      // Parse variants from response
      final variants = response
          .toString()
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s != query)
          .take(2)
          .toList();

      // Always include original query
      return [query, ...variants];
    } on Exception catch (e) {
      debugPrint('[QueryExpansionService] Error expanding query: $e');
      // Fallback to original query only
      return [query];
    }
  }

  /// Searches with all query variants and merges results using RRF
  Future<List<SearchResult>> searchWithExpandedQueries(
    String originalQuery,
    List<String> queryVariants, {
    int limit = 10,
    double? semanticWeight,
  }) async {
    final allResults = <SearchResult>[];

    // Search with each variant
    for (final variant in queryVariants) {
      final embedding = await _embeddingService.generateEmbedding(variant);
      final results = await _vectorStore.hybridSearch(
        variant,
        embedding,
        limit: limit * 2, // Get more candidates for merging
        semanticWeight: semanticWeight,
      );
      allResults.addAll(results);
    }

    // Deduplicate and merge using RRF
    return _mergeResultsWithRRF(allResults, limit);
  }

  /// Merge results from multiple queries using Reciprocal Rank Fusion
  List<SearchResult> _mergeResultsWithRRF(
    List<SearchResult> results,
    int limit,
  ) {
    const k = 60.0; // RRF constant
    final scores = <String, double>{};
    final items = <String, SearchResult>{};

    // Group by ID and calculate RRF score based on position in each list
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      scores[result.id] = (scores[result.id] ?? 0) + 1.0 / (k + i + 1);
      items[result.id] ??= result;
    }

    // Sort by RRF score
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
        'Failed to get active inference model for query expansion: $e',
      );
    }

    if (_inferenceModel == null) {
      throw Exception('No active inference model found for query expansion');
    }
  }
}
