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
  }) async {
    if (!_isInitialized) throw Exception('RAG Service not initialized');

    final stopwatch = Stopwatch()..start();

    // 1. Embed Query
    final queryEmbedding = await _embeddingService.generateEmbedding(query);
    final embeddingTime = stopwatch.elapsed;

    // 2. Hybrid Search
    final results = _vectorStore.hybridSearch(query, queryEmbedding, limit: 3);
    final searchTime = stopwatch.elapsed - embeddingTime;

    // 3. Build Context
    final context = _buildContext(results);

    // 4. Generate Response
    await _ensureInferenceModel();
    final response = await _generate(query, context);
    final generationTime = stopwatch.elapsed - searchTime - embeddingTime;

    return RAGResult(
      response: response,
      sources: results,
      metrics: includeMetrics
          ? RAGMetrics(
              embeddingTime: embeddingTime,
              searchTime: searchTime,
              generationTime: generationTime,
              chunksRetrieved: results.length,
            )
          : null,
    );
  }

  Future<void> ingestDocument(String documentId, String content) async {
    // Basic chunking logic
    final chunks = _splitIntoChunks(content, 500);

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final embedding = await _embeddingService.generateEmbedding(chunk);

      _vectorStore.insertEmbedding(
        id: '${documentId}_$i',
        documentId: documentId,
        content: chunk,
        embedding: embedding,
        metadata: {'seq': i},
      );
    }
  }

  Future<void> _ensureInferenceModel() async {
    if (_inferenceModel != null) return;
    _inferenceModel = await FlutterGemma.getActiveModel();
    if (_inferenceModel == null) {
      throw Exception(
        'Inference model not loaded. Please download/activate one.',
      );
    }
  }

  Future<String> _generate(String query, String context) async {
    final prompt =
        '''

<start_of_turn>user
Context:
$context

Question: $query

Answer based only on the provided context. If the answer is not in the context, say "I don't have enough information."
<end_of_turn>
<start_of_turn>model
''';

    final response = StringBuffer();
    final chat = await _inferenceModel!.createChat(temperature: 0.1);

    // Using dynamic to bypass analyzer issues with library types
    // ignore: avoid_dynamic_calls, FlutterGemma type mismatch
    final stream = (chat as dynamic).getChatStream(prompt: prompt) as Stream;
    await for (final token in stream) {
      // ignore: avoid_dynamic_calls, FlutterGemma type mismatch
      response.write(token?.text ?? '');
    }

    return response.toString();
  }

  String _buildContext(List<SearchResult> results) {
    if (results.isEmpty) return 'No relevant context found.';
    return results
        .asMap()
        .entries
        .map((e) => '[Source ${e.key + 1}]: ${e.value.content}')
        .join('\n\n');
  }

  List<String> _splitIntoChunks(String text, int wordsPerChunk) {
    final words = text.split(RegExp(r'\s+'));
    final chunks = <String>[];

    for (var i = 0; i < words.length; i += wordsPerChunk) {
      final end = (i + wordsPerChunk < words.length)
          ? i + wordsPerChunk
          : words.length;
      chunks.add(words.sublist(i, end).join(' '));
    }

    return chunks;
  }
}
