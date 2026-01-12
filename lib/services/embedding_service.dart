import 'package:flutter_gemma/flutter_gemma.dart';

class EmbeddingService {
  Future<List<double>> generateEmbedding(String text) async {
    final embedder = await FlutterGemma.getActiveEmbedder();

    // Note: getEmbedding might return a List<double> or a proprietary object
    // depending on version. Standardizing to List<double>.
    // Using dynamic to bypass analyzer issues with library types.
    // ignore: avoid_dynamic_calls, FlutterGemma type mismatch
    final result =
        await (embedder as dynamic).getEmbedding(text) as List<double>;
    return result;
  }
}
