import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/rag_settings_service.dart';

/// Centralized provider for managing inference model instances
///
/// This service ensures consistent model initialization across
/// RagService, QueryExpansionService, and RerankingService.
class InferenceModelProvider {
  InferenceModelProvider({this._settingsService, this._activeModelLoader});

  InferenceModel? _model;
  Future<InferenceModel>? _inFlightFuture;
  static Future<void> _chatLane = Future<void>.value();
  final RagSettingsService? _settingsService;
  final Future<InferenceModel?> Function({required int maxTokens})?
  _activeModelLoader;

  /// Gets the active inference model, initializing it if necessary
  ///
  /// Respects user-configured maxTokens from settings, falling back
  /// to the model's default configuration.
  ///
  /// Throws an [Exception] if:
  /// - The model fails to load
  /// - No active model is available (e.g., still downloading)
  Future<InferenceModel> getModel() {
    final currentModel = _model;
    if (currentModel != null) return Future.value(currentModel);
    return _inFlightFuture ??= _loadModel();
  }

  Future<InferenceModel> _loadModel() async {
    try {
      // Get maxTokens from user settings or model config
      final settings = _settingsService ?? locator<RagSettingsService>();
      final userMaxTokens = settings.maxTokens;
      final modelDefinition = ModelConfig.activeInferenceModelOrDefault(
        settings.activeInferenceModelId,
      );

      final maxTokens =
          userMaxTokens ??
          modelDefinition.contextLimit ??
          modelDefinition.maxTokens;

      final activeModelLoader =
          _activeModelLoader ?? FlutterGemma.getActiveModel;
      _model = await activeModelLoader(maxTokens: maxTokens);
    } catch (e) {
      _inFlightFuture = null;
      throw Exception(
        'Failed to get active inference model: $e. '
        'The model may still be downloading. Please wait and try again.',
      );
    }

    final loadedModel = _model;
    if (loadedModel == null) {
      _inFlightFuture = null;
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
    final cachedModel = _model;
    _model = null;
    _inFlightFuture = null;
    if (cachedModel != null) {
      unawaited(_closeModel(cachedModel));
    }
  }

  /// Releases the loaded model, used when the application is paused.
  Future<void> releaseModel() async {
    final cachedModel = _model;
    _model = null;
    _inFlightFuture = null;
    if (cachedModel != null) {
      await _closeModel(cachedModel);
    }
  }

  /// Runs one model-backed chat operation at a time.
  ///
  /// The plugin's legacy chat/session slot is mutable, so callers must use
  /// this lane even when their own work appears sequential. Each operation
  /// owns and closes its chat before the next operation starts.
  static Future<T> withSerializedChat<T>(
    InferenceModel model, {
    required double temperature,
    required Future<T> Function(InferenceChat chat) action,
  }) {
    final operation = _chatLane.then((_) async {
      final chat = await model.createChat(temperature: temperature);
      try {
        return await action(chat);
      } finally {
        try {
          await chat.close();
        } on Object catch (_) {
          // Cleanup must not replace the generation result or error.
        }
      }
    });
    _chatLane = operation.then<void>(
      (_) {},
      onError: (_, _) {},
    );
    return operation;
  }

  static Future<void> _closeModel(InferenceModel model) async {
    try {
      await model.close();
    } on Object catch (_) {
      // Best-effort release during settings/lifecycle teardown.
    }
  }
}
