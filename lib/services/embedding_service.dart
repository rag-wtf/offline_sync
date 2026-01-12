import 'package:flutter_gemma/flutter_gemma.dart';

class EmbeddingService {
  Future<List<double>> generateEmbedding(String text) async {
    final embedder = await FlutterGemma.getActiveEmbedder();

    // Note: getEmbedding might return a List<double> or a proprietary object
    // depending on version. Standardizing to List<double>.
    // Using dynamic to bypass analyzer issues with library types.
    final result = await embedder.generateEmbedding(text);
    return result;
  }
}
