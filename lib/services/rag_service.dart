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
  final EmbeddingService _embeddingService = locator<EmbeddingService>();
  final VectorStore _vectorStore = locator<VectorStore>();
  final InferenceModelProvider _inferenceModelProvider =
      locator<InferenceModelProvider>();
  final RagTokenManager _tokenManager = locator<RagTokenManager>();

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
    if (!_isInitialized) throw Exception('RAG Service not initialized');

    LoggingService.info('Performing RAG query: $query');
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

    // 2. Embed Query
    final queryEmbedding = await _embeddingService.generateEmbedding(query);
    final embeddingTime = stopwatch.elapsed;

    // 3. Hybrid Search with expanded queries
    var searchResults = <SearchResult>[];
    if (settings.queryExpansionEnabled && queryVariants.length > 1) {
      final expansionService = locator<QueryExpansionService>();
      searchResults = await expansionService.searchWithExpandedQueries(
        query,
        queryVariants,
        // coverage:ignore-start
        limit: settings.rerankingEnabled
            ? settings.rerankTopK
            : settings.searchTopK,
        // coverage:ignore-end
        documentIds: documentIds,
      );
    } else {
      // coverage:ignore-start
      searchResults = await _vectorStore.hybridSearch(
        query,
        queryEmbedding,
        limit: settings.rerankingEnabled
            ? settings.rerankTopK
            : settings.searchTopK,
        documentIds: documentIds,
      );
      // coverage:ignore-end
    }
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

    // 5. Generate Response with conversation history and token budget mgmt
    final response = await _generate(
      query,
      searchResults,
      conversationHistory: conversationHistory,
    );
    final generationTime = stopwatch.elapsed - searchTime - embeddingTime;

    final duration = stopwatch.elapsed;
    LoggingService.info('RAG query completed in ${duration.inMilliseconds}ms');

    return RAGResult(
      response: response,
      sources: searchResults,
      metrics: includeMetrics
          ? RAGMetrics(
              embeddingTime: embeddingTime,
              searchTime: searchTime,
              generationTime: generationTime,
              chunksRetrieved: searchResults.length,
              queryExpansionTime: queryExpansionTime,
              rerankingTime: rerankingTime,
              expandedQueryCount: expandedQueryCount,
            )
          : null,
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

    // 2. Embed Query
    final queryEmbedding = await _embeddingService.generateEmbedding(query);
    final embeddingTime = stopwatch.elapsed;

    // 3. Hybrid Search with expanded queries
    var searchResults = <SearchResult>[];
    if (settings.queryExpansionEnabled && queryVariants.length > 1) {
      final expansionService = locator<QueryExpansionService>();
      searchResults = await expansionService.searchWithExpandedQueries(
        query,
        queryVariants,
        // coverage:ignore-start
        limit: settings.rerankingEnabled
            ? settings.rerankTopK
            : settings.searchTopK,
        // coverage:ignore-end
        documentIds: documentIds,
      );
    } else {
      // coverage:ignore-start
      searchResults = await _vectorStore.hybridSearch(
        query,
        queryEmbedding,
        limit: settings.rerankingEnabled
            ? settings.rerankTopK
            : settings.searchTopK,
        documentIds: documentIds,
      );
      // coverage:ignore-end
    }
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

  /// Deduplicates search results by document/chunk ID and normalized content
  static List<SearchResult> deduplicateResults(List<SearchResult> results) {
    final seen = <String>{};
    return results.where((r) {
      final docId = r.metadata['documentId'] ?? r.id;
      final key = '${docId}_${r.content.trim()}';
      return seen.add(key);
    }).toList();
  }

  /// Cleans trailing disclaimer artifacts from the model response when an answer was already provided
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

  Future<String> _generate(
    String query,
    List<SearchResult> searchResults, {
    List<String>? conversationHistory,
  }) async {
    final settings = locator<RagSettingsService>();
    final modelConfig = ModelConfig.activeInferenceModelOrDefault(
      settings.activeInferenceModelId,
    );
    // Calculate token budget honoring user maxTokens override
    final maxTokens = settings.maxTokens ?? modelConfig.maxTokens;
    final outputReserve = (maxTokens * RagConstants.outputReserveRatio).floor();
    final queryTokens = _tokenManager.estimateTokens(query);
    final rawAvailable = maxTokens - outputReserve - queryTokens;
    if (rawAvailable <= 0) {
      LoggingService.warning(
        'Token budget exhausted: maxTokens=$maxTokens, '
        'reserve=$outputReserve, queryTokens=$queryTokens',
      );
    }
    final availableForPrompt = max(0, rawAvailable);

    // Allocate using defined ratios
    final contextBudget = (availableForPrompt * RagConstants.contextBudgetRatio)
        .floor();
    final historyBudget = (availableForPrompt * RagConstants.historyBudgetRatio)
        .floor();

    final historySection = _tokenManager.buildHistoryWithBudget(
      conversationHistory?.take(settings.maxHistoryMessages).toList() ?? [],
      historyBudget,
    );
    final context = _buildContextWithBudget(searchResults, contextBudget);

    final prompt = '''
${historySection}Context:
$context

Question: $query

Instructions:
- Answer the question accurately and concisely based on the context above.
- If the context does not contain relevant information to answer the question, say "I don't have enough information."
- Do not append disclaimer phrases or repeat instructions after answering.''';

    final response = StringBuffer();
    final inferenceModel = await _inferenceModelProvider.getModel();
    final chat = await inferenceModel.createChat(temperature: 0.1);

    // Initialize the chat session
    await chat.initSession();

    // Add the prompt as a query
    await chat.addQuery(Message(text: prompt, isUser: true));

    // Get the streaming response with inactivity timeout
    final stream = chat
        .generateChatResponseAsync()
        .timeout(const Duration(seconds: 30));
    await for (final modelResponse in stream) {
      if (modelResponse is TextResponse) {
        response.write(modelResponse.token);
      }
    }

    return cleanResponse(response.toString());
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
    // Calculate token budget honoring user maxTokens override
    final maxTokens = settings.maxTokens ?? modelConfig.maxTokens;
    final outputReserve = (maxTokens * RagConstants.outputReserveRatio).floor();
    final queryTokens = _tokenManager.estimateTokens(query);
    final rawAvailable = maxTokens - outputReserve - queryTokens;
    if (rawAvailable <= 0) {
      LoggingService.warning(
        'Token budget exhausted: maxTokens=$maxTokens, '
        'reserve=$outputReserve, queryTokens=$queryTokens',
      );
    }
    final availableForPrompt = max(0, rawAvailable);

    // Allocate using defined ratios
    final contextBudget = (availableForPrompt * RagConstants.contextBudgetRatio)
        .floor();
    final historyBudget = (availableForPrompt * RagConstants.historyBudgetRatio)
        .floor();

    final historySection = _tokenManager.buildHistoryWithBudget(
      conversationHistory?.take(settings.maxHistoryMessages).toList() ?? [],
      historyBudget,
    );
    final context = _buildContextWithBudget(searchResults, contextBudget);

    final prompt = '''
${historySection}Context:
$context

Question: $query

Instructions:
- Answer the question accurately and concisely based on the context above.
- If the context does not contain relevant information to answer the question, say "I don't have enough information."
- Do not append disclaimer phrases or repeat instructions after answering.''';

    LoggingService.debug(
      'Generated prompt (${prompt.length} chars). '
      'Budget: context=$contextBudget, history=$historyBudget',
    );

    final inferenceModel = await _inferenceModelProvider.getModel();
    final chat = await inferenceModel.createChat(temperature: 0.1);

    // Initialize the chat session
    await chat.initSession();

    // Add the prompt as a query
    await chat.addQuery(Message(text: prompt, isUser: true));

    // Stream tokens as they arrive with inactivity timeout
    final stream = chat
        .generateChatResponseAsync()
        .timeout(const Duration(seconds: 30));
    await for (final modelResponse in stream) {
      if (modelResponse is TextResponse) {
        yield modelResponse.token;
      }
    }
  }

  /// Build context from search results with token budget
  String _buildContextWithBudget(List<SearchResult> results, int tokenBudget) {
    if (results.isEmpty) return 'No relevant context found.';

    // Results already sorted by relevance score
    final chunks = <String>[];
    var tokens = 0;

    for (final result in results) {
      final chunkText = '[Source ${chunks.length + 1}]: ${result.content}';
      final chunkTokens = _tokenManager.estimateTokens(chunkText);

      if (tokens + chunkTokens <= tokenBudget) {
        chunks.add(chunkText);
        tokens += chunkTokens;
      } else {
        break; // Skip lower-relevance chunks
      }
    }

    return chunks.isEmpty ? 'No relevant context found.' : chunks.join('\n\n');
  }
}
