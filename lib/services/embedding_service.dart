import 'package:flutter_gemma/flutter_gemma.dart';

class EmbeddingService {
  EmbeddingService({Future<EmbeddingModel> Function()? activeEmbedderLoader})
    : _activeEmbedderLoader =
          activeEmbedderLoader ?? FlutterGemma.getActiveEmbedder;

  final Future<EmbeddingModel> Function() _activeEmbedderLoader;

  Future<List<double>> generateEmbedding(String text) async {
    // Rely on explicit initialization from ModelManagementService/Startup
    // (Settings > Select Model or Startup Auto-Load)
    // This avoids race conditions where multiple chunks try to conflictingly
    // lazy-initialize the model at the same time.
    final embedder = await _activeEmbedderLoader();

    // Note: getEmbedding might return a List<double> or a proprietary object
    // depending on version. Standardizing to List<double>.
    // Using dynamic to bypass analyzer issues with library types.
    final result = await embedder
        .generateEmbedding(text)
        .timeout(const Duration(seconds: 30));
    return result;
  }
}
