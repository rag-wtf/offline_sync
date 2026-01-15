import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/vector_store.dart';

class RAGResult {
  RAGResult({required this.response, required this.sources, this.metrics});
  final String response;
  final List<SearchResult> sources;
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

class RAGMetrics {
  RAGMetrics({
    required this.embeddingTime,
    required this.searchTime,
    required this.generationTime,
    required this.chunksRetrieved,
  });
  final Duration embeddingTime;
  final Duration searchTime;
  final Duration generationTime;
  final int chunksRetrieved;
}

class RagService {
  final EmbeddingService _embeddingService = locator<EmbeddingService>();
  final VectorStore _vectorStore = locator<VectorStore>();

  InferenceModel? _inferenceModel;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _vectorStore.initialize();
    _isInitialized = true;
  }

  Future<RAGResult> askWithRAG(
    String query, {
    bool includeMetrics = false,
    List<String>? conversationHistory,
  }) async {
    if (!_isInitialized) throw Exception('RAG Service not initialized');

    final stopwatch = Stopwatch()..start();

    // 1. Embed Query
    final queryEmbedding = await _embeddingService.generateEmbedding(query);
    final embeddingTime = stopwatch.elapsed;

    // 2. Hybrid Search
    final searchResults = await _vectorStore.hybridSearch(
      query,
      queryEmbedding,
      limit: 3,
    );
    final searchTime = stopwatch.elapsed - embeddingTime;

    // 3. Build Context
    final context = _buildContext(searchResults);

    // 4. Generate Response with conversation history
    await _ensureInferenceModel();
    final response = await _generate(
      query,
      context,
      conversationHistory: conversationHistory,
    );
    final generationTime = stopwatch.elapsed - searchTime - embeddingTime;

    return RAGResult(
      response: response,
      sources: searchResults,
      metrics: includeMetrics
          ? RAGMetrics(
              embeddingTime: embeddingTime,
              searchTime: searchTime,
              generationTime: generationTime,
              chunksRetrieved: searchResults.length,
            )
          : null,
    );
  }

  /// Stream-based version of askWithRAG that yields tokens as they arrive
  Stream<RAGStreamEvent> askWithRAGStream(
    String query, {
    bool includeMetrics = false,
    List<String>? conversationHistory,
  }) async* {
    if (!_isInitialized) throw Exception('RAG Service not initialized');

    final stopwatch = Stopwatch()..start();

    // 1. Embed Query
    final queryEmbedding = await _embeddingService.generateEmbedding(query);
    final embeddingTime = stopwatch.elapsed;

    // 2. Hybrid Search
    final searchResults = await _vectorStore.hybridSearch(
      query,
      queryEmbedding,
      limit: 3,
    );
    final searchTime = stopwatch.elapsed - embeddingTime;

    // 3. Emit metadata event with sources
    yield RAGMetadataEvent(
      sources: searchResults,
      metrics: includeMetrics
          ? RAGMetrics(
              embeddingTime: embeddingTime,
              searchTime: searchTime,
              generationTime: Duration.zero,
              chunksRetrieved: searchResults.length,
            )
          : null,
    );

    // 4. Build Context
    final context = _buildContext(searchResults);

    // 5. Stream tokens from generation
    await _ensureInferenceModel();
    await for (final token in _generateStream(
      query,
      context,
      conversationHistory: conversationHistory,
    )) {
      yield RAGTokenEvent(token);
    }

    // 6. Emit completion event
    yield RAGCompleteEvent();
  }

  Future<void> ingestDocument(String documentId, String content) async {
    // Chunk text to fit embedding model's 256 token limit
    // (254 usable after special tokens)
    // Using very conservative 80 words (~100-160 tokens for code/markdown content)
    // Markdown/code can tokenize at 2-3 tokens per word vs 1.3 for regular text
    final chunks = _splitIntoChunks(content, 80);

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

  Future<void> _ensureInferenceModel() async {
    if (_inferenceModel != null) return;

    try {
      _inferenceModel = await FlutterGemma.getActiveModel();
    } catch (e) {
      throw Exception(
        'Failed to get active inference model: $e. '
        'The model may still be downloading. Please wait and try again.',
      );
    }

    if (_inferenceModel == null) {
      throw Exception(
        'No active inference model found. '
        'The model may still be downloading. Please wait and try again, '
        'or check the Settings screen to manually download a model.',
      );
    }
  }

  Future<String> _generate(
    String query,
    String context, {
    List<String>? conversationHistory,
  }) async {
    // Build conversation history section
    final historySection =
        conversationHistory != null && conversationHistory.isNotEmpty
        ? '''
Previous conversation:
${conversationHistory.take(5).join('\n')}

'''
        : '';

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
    final chat = await _inferenceModel!.createChat(temperature: 0.1);

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
    String context, {
    List<String>? conversationHistory,
  }) async* {
    // Build conversation history section
    final historySection =
        conversationHistory != null && conversationHistory.isNotEmpty
        ? '''
Previous conversation:
${conversationHistory.take(5).join('\n')}

'''
        : '';

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

    final chat = await _inferenceModel!.createChat(temperature: 0.1);

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

  String _buildContext(List<SearchResult> results) {
    if (results.isEmpty) return 'No relevant context found.';
    return results
        .asMap()
        .entries
        .map((e) => '[Source ${e.key + 1}]: ${e.value.content}')
        .join('\n\n');
  }

  /// Split text into chunks using character limit with line-based boundaries
  /// This handles markdown content (bullet points, tables, code) that
  /// lacks sentence endings
  List<String> _splitIntoChunks(
    String text,
    int targetWords, // kept for API compatibility but now uses chars internally
  ) {
    // Use character limit: ~500 chars ≈ ~100 tokens for mixed content
    // This provides a safe margin under the 254 token limit
    const maxChars = 500;

    // Split on newlines to preserve markdown structure
    final lines = text.split('\n');

    if (text.length <= maxChars) return [text];

    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final line in lines) {
      // If adding this line would exceed limit, finalize current chunk
      if (buffer.length + line.length + 1 > maxChars && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }

      // If a single line exceeds the limit, split it by characters
      if (line.length > maxChars) {
        // Finalize current buffer first
        if (buffer.isNotEmpty) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        // Split long line into fixed-size chunks
        for (var i = 0; i < line.length; i += maxChars) {
          final end = (i + maxChars < line.length) ? i + maxChars : line.length;
          chunks.add(line.substring(i, end));
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
}
