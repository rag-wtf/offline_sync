import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/rag_settings_service.dart';

/// A model instance and the persisted identity it was loaded for.
class PinnedEmbeddingModel {
  const PinnedEmbeddingModel({required this.id, required this.model});

  final String id;
  final EmbeddingModel model;
}

/// Serializes operations that must not overlap an embedding-model activation.
class EmbeddingModelCoordinator {
  Future<void> _lane = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final next = _lane.then<T>((_) => operation());
    _lane = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }
}

class EmbeddingService {
  EmbeddingService({
    Future<EmbeddingModel> Function()? activeEmbedderLoader,
    this._activeEmbeddingIdLoader,
  }) : _activeEmbedderLoader =
           activeEmbedderLoader ?? FlutterGemma.getActiveEmbedder;

  final Future<EmbeddingModel> Function() _activeEmbedderLoader;
  final Future<String?> Function()? _activeEmbeddingIdLoader;

  Future<PinnedEmbeddingModel> pinActiveModel() async {
    final id = await (_activeEmbeddingIdLoader ?? _loadActiveEmbeddingId)();
    if (id == null || id.isEmpty) {
      throw StateError('No active embedding model set');
    }
    return PinnedEmbeddingModel(
      id: id,
      model: await _activeEmbedderLoader(),
    );
  }

  Future<List<double>> generateEmbedding(
    String text, {
    EmbeddingModel? model,
  }) async {
    // Rely on explicit initialization from ModelManagementService/Startup
    // (Settings > Select Model or Startup Auto-Load)
    // This avoids race conditions where multiple chunks try to conflictingly
    // lazy-initialize the model at the same time.
    final embedder = model ?? await _activeEmbedderLoader();

    // Note: getEmbedding might return a List<double> or a proprietary object
    // depending on version. Standardizing to List<double>.
    // Using dynamic to bypass analyzer issues with library types.
    final result = await embedder
        .generateEmbedding(text)
        .timeout(const Duration(seconds: 30));
    return result;
  }

  Future<String?> _loadActiveEmbeddingId() async {
    return locator<RagSettingsService>().activeEmbeddingModelId;
  }
}
