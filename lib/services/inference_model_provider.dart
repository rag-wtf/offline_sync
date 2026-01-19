import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/rag_settings_service.dart';

/// Centralized provider for managing inference model instances
///
/// This service ensures consistent model initialization across
/// RagService, QueryExpansionService, and RerankingService.
class InferenceModelProvider {
  InferenceModel? _model;

  /// Gets the active inference model, initializing it if necessary
  ///
  /// Respects user-configured maxTokens from settings, falling back
  /// to the model's default configuration.
  ///
  /// Throws an [Exception] if:
  /// - The model fails to load
  /// - No active model is available (e.g., still downloading)
  Future<InferenceModel> getModel() async {
    // Use local variable to avoid potential null safety issues
    final currentModel = _model;
    if (currentModel != null) return currentModel;

    try {
      // Get maxTokens from user settings or model config
      final settings = locator<RagSettingsService>();
      final userMaxTokens = settings.maxTokens;

      final maxTokens =
          userMaxTokens ??
          ModelConfig.allModels
              .firstWhere(
                (m) => m.type == AppModelType.inference,
                orElse: () => InferenceModels.gemma3_270M,
              )
              .maxTokens;

      _model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
      );
    } catch (e) {
      throw Exception(
        'Failed to get active inference model: $e. '
        'The model may still be downloading. Please wait and try again.',
      );
    }

    final loadedModel = _model;
    if (loadedModel == null) {
      throw Exception(
        'No active inference model found. '
        'The model may still be downloading. Please wait and try again, '
        'or check the Settings screen to manually download a model.',
      );
    }

    return loadedModel;
  }

  /// Clears the cached model instance
  ///
  /// Call this when the active model changes (e.g., user switches models
  /// in settings) to ensure the next call to [getModel] retrieves the
  /// new active model.
  void clearCache() {
    _model = null;
  }
}
