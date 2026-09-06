import 'dart:async';
import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/query_expansion_service.dart';
import 'package:offline_sync/services/rag_constants.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/rag_token_manager.dart';
import 'package:offline_sync/services/reranking_service.dart';
import 'package:offline_sync/services/vector_store.dart';

/// Result of a RAG query containing the text response and source documents
class RAGResult {
  RAGResult({required this.response, required this.sources, this.metrics});

  /// The generated text response from the model
  final String response;

  /// The list of source document chunks used for generation
  final List<SearchResult> sources;

  /// Performance metrics for the RAG operation (optional)
  final RAGMetrics? metrics;
}

// Stream events for streaming RAG responses
abstract class RAGStreamEvent {}

class RAGMetadataEvent extends RAGStreamEvent {
  RAGMetadataEvent({required this.sources, this.metrics});
  final List<SearchResult> sources;
  final RAGMetrics? metrics;
}

class RAGTokenEvent extends RAGStreamEvent {
  RAGTokenEvent(this.token);
  final String token;
}

class RAGCompleteEvent extends RAGStreamEvent {}

/// Performance metrics for RAG operations
class RAGMetrics {
  RAGMetrics({
    required this.embeddingTime,
    required this.searchTime,
    required this.generationTime,
    required this.chunksRetrieved,
    this.queryExpansionTime,
    this.rerankingTime,
    this.expandedQueryCount,
  });

  /// Time taken to generate the query embedding
  final Duration embeddingTime;

  /// Time taken for the vector store search
  final Duration searchTime;

  /// Time taken for LLM generation
  final Duration generationTime;

  /// Number of document chunks retrieved from the vector store
  final int chunksRetrieved;

  /// Time taken for query expansion (if enabled)
  final Duration? queryExpansionTime;

  /// Time taken for reranking (if enabled)
  final Duration? rerankingTime;

  /// Number of expanded queries generated (if enabled)
  final int? expandedQueryCount;
}

class RagService {
  RagService({EmbeddingModelCoordinator? embeddingCoordinator})
    : _embeddingCoordinator =
          embeddingCoordinator ??
          (locator.isRegistered<EmbeddingModelCoordinator>()
              ? locator<EmbeddingModelCoordinator>()
              : EmbeddingModelCoordinator());

  final EmbeddingService _embeddingService = locator<EmbeddingService>();
  final VectorStore _vectorStore = locator<VectorStore>();
  final InferenceModelProvider _inferenceModelProvider =
      locator<InferenceModelProvider>();
  final RagTokenManager _tokenManager = locator<RagTokenManager>();
  final EmbeddingModelCoordinator _embeddingCoordinator;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _vectorStore.initialize();
    _isInitialized = true;
  }

  /// Performs a Retrieval-Augmented Generation (RAG) query
  ///
  /// 1. Expands the query (if enabled)
  /// 2. Embeds the query using the embedding model
  /// 3. Performs hybrid search in the vector store
  /// 4. Reranks results using LLM (if enabled)
  /// 5. Generates a response based on retrieved context
  Future<RAGResult> askWithRAG(
    String query, {
    bool includeMetrics = false,
    List<String>? conversationHistory,
    List<String>? documentIds,
  }) async {
    final response = StringBuffer();
    var sources = <SearchResult>[];
    RAGMetrics? metrics;
    await for (final event in askWithRAGStream(
      query,
      includeMetrics: includeMetrics,
      conversationHistory: conversationHistory,
      documentIds: documentIds,
    )) {
      if (event is RAGMetadataEvent) {
        sources = event.sources;
        metrics = event.metrics;
      } else if (event is RAGTokenEvent) {
        response.write(event.token);
      }
    }
    return RAGResult(
      response: cleanResponse(response.toString()),
      sources: sources,
      metrics: metrics,
    );
  }

  /// Stream-based version of askWithRAG that yields tokens as they arrive
  Stream<RAGStreamEvent> askWithRAGStream(
    String query, {
    bool includeMetrics = false,
    List<String>? conversationHistory,
    List<String>? documentIds,
  }) async* {
    if (!_isInitialized) throw Exception('RAG Service not initialized');

    final settings = locator<RagSettingsService>();
    final stopwatch = Stopwatch()..start();

    // 1. Query Expansion (if enabled)
    Duration? queryExpansionTime;
    int? expandedQueryCount;
    var queryVariants = <String>[query];

    if (settings.queryExpansionEnabled) {
      final expansionService = locator<QueryExpansionService>();
      final expansionStart = stopwatch.elapsed;
      queryVariants = await expansionService.expandQuery(query);
      queryExpansionTime = stopwatch.elapsed - expansionStart;
      expandedQueryCount = queryVariants.length;
    }

    // 2-3. Pin query embedding and vector search to one embedder identity.
    var searchResults = await _retrieveWithPinnedEmbedding(
      query,
      queryVariants,
      settings: settings,
      documentIds: documentIds,
    );
    final embeddingTime = stopwatch.elapsed;
    final searchTime = stopwatch.elapsed - embeddingTime;

    // 4. Reranking (if enabled)
    Duration? rerankingTime;
    if (settings.rerankingEnabled && searchResults.isNotEmpty) {
      final rerankService = locator<RerankingService>();
      final rerankStart = stopwatch.elapsed;
      searchResults = await rerankService.rerank(
        query,
        searchResults,
        topK: settings.rerankTopK,
      );
      rerankingTime = stopwatch.elapsed - rerankStart;
      // Take top searchTopK for generation
      searchResults = searchResults.take(settings.searchTopK).toList();
    }

    // Deduplicate search results
    searchResults = deduplicateResults(searchResults);

    // 5. Emit metadata event with sources
    yield RAGMetadataEvent(
      sources: searchResults,
      metrics: includeMetrics
          ? RAGMetrics(
              embeddingTime: embeddingTime,
              searchTime: searchTime,
              generationTime: Duration.zero,
              chunksRetrieved: searchResults.length,
              queryExpansionTime: queryExpansionTime,
              rerankingTime: rerankingTime,
              expandedQueryCount: expandedQueryCount,
            )
          : null,
    );

    // 6. Stream tokens from generation with token budget management
    await for (final token in _generateStream(
      query,
      searchResults,
      conversationHistory: conversationHistory,
    )) {
      yield RAGTokenEvent(token);
    }

    // 8. Emit completion event
    yield RAGCompleteEvent();
  }

  Future<List<SearchResult>> _retrieveWithPinnedEmbedding(
    String query,
    List<String> queryVariants, {
    required RagSettingsService settings,
    List<String>? documentIds,
  }) {
    return _embeddingCoordinator.run(() async {
      final pinned = await _embeddingService.pinActiveModel();
      final limit = settings.rerankingEnabled
          ? settings.rerankTopK
          : settings.searchTopK;
      if (settings.queryExpansionEnabled && queryVariants.length > 1) {
        return locator<QueryExpansionService>().searchWithExpandedQueries(
          query,
          queryVariants,
          limit: limit,
          documentIds: documentIds,
          pinnedEmbedder: pinned.model,
          embeddingModelId: pinned.id,
        );
      }
      final queryEmbedding = await _embeddingService.generateEmbedding(
        query,
        model: pinned.model,
      );
      return _vectorStore.hybridSearch(
        query,
        queryEmbedding,
        limit: limit,
        documentIds: documentIds,
        embeddingModelId: pinned.id,
      );
    });
  }

  /// Deduplicates search results by document/chunk ID and normalized content
  static List<SearchResult> deduplicateResults(List<SearchResult> results) {
    final seen = <String>{};
    return results.where((r) {
      final docId = r.metadata['documentId'] ?? r.id;
      final key = '${docId}_${r.content.trim()}';
      return seen.add(key);
    }).toList();
  }

  /// Cleans trailing disclaimer artifacts from the model response when an
  /// answer was already provided
  static String cleanResponse(String response) {
    var cleaned = response.trim();
    final trailingDisclaimerRegex = RegExp(
      r"""(\n|\s)*(If the answer is not in the (provided\s*)?context,?\s*(say\s*)?)?"?I don'?t have enough information\.?"?(\n|\s)*$""",
      caseSensitive: false,
    );
    final match = trailingDisclaimerRegex.firstMatch(cleaned);
    if (match != null && match.start >= 15) {
      cleaned = cleaned.substring(0, match.start).trim();
    }
    return cleaned;
  }

  /// Stream tokens from the model as they're generated
  Stream<String> _generateStream(
    String query,
    List<SearchResult> searchResults, {
    List<String>? conversationHistory,
  }) async* {
    final settings = locator<RagSettingsService>();
    final modelConfig = ModelConfig.activeInferenceModelOrDefault(
      settings.activeInferenceModelId,
    );
    final contextLimit = modelConfig.contextLimit ?? modelConfig.maxTokens;
    final maxTokens = min(settings.maxTokens ?? contextLimit, contextLimit);
    final controller = StreamController<String>();
    unawaited(() async {
      try {
        final inferenceModel = await _inferenceModelProvider.getModel();
        await _inferenceModelProvider.runSerializedChat(
          inferenceModel,
          temperature: 0.1,
          action: (chat) async {
            await chat.initSession();
            final prompt = await _buildPrompt(
              chat: chat,
              query: query,
              searchResults: searchResults,
              conversationHistory: conversationHistory,
              maxTokens: maxTokens,
            );
            final exactPromptTokens = await _countPromptTokens(chat, prompt);
            LoggingService.debug(
              'Prompt token count: $exactPromptTokens/$maxTokens',
            );
            await chat.addQuery(Message(text: prompt, isUser: true));

            final stream = chat.generateChatResponseAsync().timeout(
              const Duration(seconds: 30),
            );
            await for (final modelResponse in stream) {
              if (modelResponse is TextResponse) {
                controller.add(modelResponse.token);
              }
            }
          },
        );
      } on Object catch (error, stack) {
        controller.addError(error, stack);
      } finally {
        await controller.close();
      }
    }());

    await for (final token in controller.stream) {
      yield token;
    }
  }

  /// Build context from search results with token budget
  Future<int> _countPromptTokens(InferenceChat chat, String prompt) async {
    try {
      final session = chat.session;
      return await _tokenManager.countTokens(
        prompt,
        exactCounter: session.sizeInTokens,
      );
    } on Object catch (_) {
      return _tokenManager.estimateTokens(prompt);
    }
  }

  Future<String> _buildPrompt({
    required InferenceChat chat,
    required String query,
    required List<SearchResult> searchResults,
    required List<String>? conversationHistory,
    required int maxTokens,
  }) {
    final settings = locator<RagSettingsService>();
    final promptLimit = max(
      1,
      maxTokens - (maxTokens * RagConstants.outputReserveRatio).floor(),
    );
    return _tokenManager.buildPromptWithinBudget(
      query: query,
      history:
          conversationHistory?.take(settings.maxHistoryMessages).toList() ??
          const [],
      context: searchResults.map((result) => result.content).toList(),
      maxTokens: promptLimit,
      countTokens: (text) => _countPromptTokens(chat, text),
    );
  }
}
