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

  Future<void> ingestDocument(String documentId, String content) async {
    // Basic chunking logic
    final chunks = _splitIntoChunks(content, 500);

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

    // Using dynamic to bypass analyzer issues with library types
    // ignore: FlutterGemma type mismatch
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

  /// Split text into chunks using sentence boundaries with overlap
  /// This provides better semantic coherence than word-based chunking
  List<String> _splitIntoChunks(
    String text,
    int targetWords,
  ) {
    // Split into sentences using regex (. ! ?)
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (sentences.isEmpty) return [text];
    if (sentences.length == 1) return sentences;

    final chunks = <String>[];
    final buffer = <String>[];
    var wordCount = 0;

    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final sentenceWords = sentence.split(RegExp(r'\s+')).length;

      // Add sentence to buffer
      buffer.add(sentence);
      wordCount += sentenceWords;

      // Check if we've reached target size or end of text
      final isLastSentence = i == sentences.length - 1;
      if (wordCount >= targetWords || isLastSentence) {
        chunks.add(buffer.join(' '));

        // Calculate overlap for next chunk (15% of target)
        if (!isLastSentence) {
          final overlapWords = (targetWords * 0.15).toInt();
          var overlapCount = 0;
          buffer.clear();
          wordCount = 0;

          // Add sentences from end for overlap
          for (var j = buffer.length - 1; j >= 0; j--) {
            final s = sentences[i - j];
            final w = s.split(RegExp(r'\s+')).length;
            if (overlapCount + w <= overlapWords) {
              buffer.insert(0, s);
              overlapCount += w;
              wordCount += w;
            } else {
              break;
            }
          }
        }
      }
    }

    return chunks.isEmpty ? [text] : chunks;
  }
}
