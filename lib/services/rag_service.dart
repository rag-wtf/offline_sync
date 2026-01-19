import 'dart:math';

import 'package:flutter/foundation.dart';
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
        limit: settings.rerankingEnabled
            ? settings.rerankTopK
            : settings.searchTopK,
        documentIds: documentIds,
      );
    } else {
      searchResults = await _vectorStore.hybridSearch(
        query,
        queryEmbedding,
        limit: settings.rerankingEnabled
            ? settings.rerankTopK
            : settings.searchTopK,
        documentIds: documentIds,
      );
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
        limit: settings.rerankingEnabled ? settings.rerankTopK : 3,
        documentIds: documentIds,
      );
    } else {
      searchResults = await _vectorStore.hybridSearch(
        query,
        queryEmbedding,
        limit: settings.rerankingEnabled ? settings.rerankTopK : 3,
        documentIds: documentIds,
      );
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
      // Take top 3 for generation
      searchResults = searchResults.take(3).toList();
    }

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

  Future<void> ingestDocument(String documentId, String content) async {
    final settings = locator<RagSettingsService>();

    // Chunk text to fit embedding model's 256 token limit
    // (254 usable after special tokens)
    // Using very conservative 80 words (~100-160 tokens for code/markdown content)
    // Markdown/code can tokenize at 2-3 tokens per word vs 1.3 for regular text
    final chunks = splitIntoChunks(
      content,
      80,
      overlapPercent: settings.chunkOverlapPercent,
    );

    // Collect all embeddings first
    final embeddingDataList = <EmbeddingData>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final embedding = await _embeddingService.generateEmbedding(chunk);

      embeddingDataList.add(
        EmbeddingData(
          id: '${documentId}_$i',
          documentId: documentId,
          content: chunk,
          embedding: embedding,
          metadata: {'seq': i},
        ),
      );
    }

    // Batch insert all embeddings in a single transaction
    _vectorStore.insertEmbeddingsBatch(embeddingDataList);
  }

  Future<String> _generate(
    String query,
    List<SearchResult> searchResults, {
    List<String>? conversationHistory,
  }) async {
    // Get max tokens from model config
    final modelConfig = ModelConfig.allModels.firstWhere(
      (m) => m.type == AppModelType.inference,
      orElse: () => InferenceModels.gemma3_270M,
    );

    // Calculate token budget using constants from RagConstants
    final maxTokens = modelConfig.maxTokens;
    final outputReserve = (maxTokens * RagConstants.outputReserveRatio).floor();
    final queryTokens = _tokenManager.estimateTokens(query);
    final availableForPrompt = maxTokens - outputReserve - queryTokens;

    // Allocate using defined ratios
    final contextBudget = (availableForPrompt * RagConstants.contextBudgetRatio)
        .floor();
    final historyBudget = (availableForPrompt * RagConstants.historyBudgetRatio)
        .floor();

    // Build components within budget
    final settings = locator<RagSettingsService>();
    final historySection = _tokenManager.buildHistoryWithBudget(
      conversationHistory?.take(settings.maxHistoryMessages).toList() ?? [],
      historyBudget,
    );
    final context = _buildContextWithBudget(searchResults, contextBudget);

    final prompt =
        '''

<start_of_turn>user
${historySection}Context:
$context

Question: $query

Answer based only on the provided context. If the answer is not in the context, say "I don't have enough information."
<end_of_turn>
<start_of_turn>model
''';

    final response = StringBuffer();
    final inferenceModel = await _inferenceModelProvider.getModel();
    final chat = await inferenceModel.createChat(temperature: 0.1);

    // Initialize the chat session
    await chat.initSession();

    // Add the prompt as a query
    await chat.addQuery(Message(text: prompt, isUser: true));

    // Get the streaming response
    final stream = chat.generateChatResponseAsync();
    await for (final modelResponse in stream) {
      if (modelResponse is TextResponse) {
        response.write(modelResponse.token);
      }
    }

    return response.toString();
  }

  /// Stream tokens from the model as they're generated
  Stream<String> _generateStream(
    String query,
    List<SearchResult> searchResults, {
    List<String>? conversationHistory,
  }) async* {
    // Get max tokens from model config
    final modelConfig = ModelConfig.allModels.firstWhere(
      (m) => m.type == AppModelType.inference,
      orElse: () => InferenceModels.gemma3_270M,
    );

    // Calculate token budget using constants from RagConstants
    final maxTokens = modelConfig.maxTokens;
    final outputReserve = (maxTokens * RagConstants.outputReserveRatio).floor();
    final queryTokens = _tokenManager.estimateTokens(query);
    final availableForPrompt = maxTokens - outputReserve - queryTokens;

    // Allocate using defined ratios
    final contextBudget = (availableForPrompt * RagConstants.contextBudgetRatio)
        .floor();
    final historyBudget = (availableForPrompt * RagConstants.historyBudgetRatio)
        .floor();

    // Build components within budget
    final settings = locator<RagSettingsService>();
    final historySection = _tokenManager.buildHistoryWithBudget(
      conversationHistory?.take(settings.maxHistoryMessages).toList() ?? [],
      historyBudget,
    );
    final context = _buildContextWithBudget(searchResults, contextBudget);

    final prompt =
        '''

<start_of_turn>user
${historySection}Context:
$context

Question: $query

Answer based only on the provided context. If the answer is not in the context, say "I don't have enough information."
<end_of_turn>
<start_of_turn>model
''';

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

    // Stream tokens as they arrive
    final stream = chat.generateChatResponseAsync();
    await for (final modelResponse in stream) {
      if (modelResponse is TextResponse) {
        yield modelResponse.token;
      }
    }
  }

  /// Split text into chunks using character limit with line-based boundaries
  /// This handles markdown content (bullet points, tables, code) that
  /// lacks sentence endings. Implements sliding window with configurable
  /// overlap.
  @visibleForTesting
  List<String> splitIntoChunks(
    String text,
    int targetWords, {
    double overlapPercent = 0.15,
  }) {
    // Use character limit from RagConstants
    const maxChars = RagConstants.maxCharsPerChunk;
    final overlapChars = (maxChars * overlapPercent).round();

    // Split on newlines to preserve markdown structure
    final lines = text.split('\n');

    if (text.length <= maxChars) return [text];

    final chunks = <String>[];
    final buffer = StringBuffer();
    var previousChunkTail = '';

    for (final line in lines) {
      // If adding this line would exceed limit, finalize current chunk
      if (buffer.length + line.length + 1 > maxChars && buffer.isNotEmpty) {
        final chunk = buffer.toString().trim();
        chunks.add(chunk);

        // Save the tail for overlap
        if (overlapChars > 0 && chunk.length > overlapChars) {
          previousChunkTail = chunk.substring(
            max(0, chunk.length - overlapChars),
          );
        }

        buffer.clear();

        // Add overlap from previous chunk to new chunk
        if (previousChunkTail.isNotEmpty) {
          buffer
            ..write(previousChunkTail)
            ..write('\n');
        }
      }

      // If a single line exceeds the limit, split it by characters
      if (line.length > maxChars) {
        // Finalize current buffer first
        if (buffer.isNotEmpty) {
          final chunk = buffer.toString().trim();
          chunks.add(chunk);

          if (overlapChars > 0 && chunk.length > overlapChars) {
            previousChunkTail = chunk.substring(
              max(0, chunk.length - overlapChars),
            );
          }

          buffer.clear();
        }

        // Split long line into fixed-size chunks with overlap
        for (var i = 0; i < line.length; i += maxChars - overlapChars) {
          final end = (i + maxChars < line.length) ? i + maxChars : line.length;
          final lineChunk = line.substring(i, end);
          chunks.add(lineChunk);

          if (overlapChars > 0 && lineChunk.length > overlapChars) {
            previousChunkTail = lineChunk.substring(
              max(0, lineChunk.length - overlapChars),
            );
          }
        }
      } else {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line);
      }
    }

    // Add remaining content
    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
    }

    return chunks.where((c) => c.isNotEmpty).toList();
  }

  /// Build context from search results with token budget
  String _buildContextWithBudget(
    List<SearchResult> results,
    int tokenBudget,
  ) {
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
