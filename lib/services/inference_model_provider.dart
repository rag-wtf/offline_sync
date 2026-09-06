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
  static Future<void> _operationLane = Future<void>.value();
  var _modelGeneration = 0;
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
    final inFlight = _inFlightFuture;
    if (inFlight != null) return inFlight;

    // Queue cache hits too: model management uses this same lane while it
    // releases/deletes an active model.
    final generation = _modelGeneration;
    final operation = _enqueue(() async {
      final currentModel = _model;
      if (currentModel != null) return currentModel;
      return _loadModel(generation);
    });
    _inFlightFuture = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_inFlightFuture, operation)) {
            _inFlightFuture = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_inFlightFuture, operation)) {
            _inFlightFuture = null;
          }
        },
      ),
    );
    return operation;
  }

  Future<InferenceModel> _loadModel(int generation) async {
    InferenceModel? loadedModel;
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
      loadedModel = await activeModelLoader(maxTokens: maxTokens);
    } catch (e) {
      throw Exception(
        'Failed to get active inference model: $e. '
        'The model may still be downloading. Please wait and try again.',
      );
    }

    if (loadedModel == null) {
      throw Exception(
        'No active inference model found. '
        'The model may still be downloading. Please wait and try again, '
        'or check the Settings screen to manually download a model.',
      );
    }

    if (generation != _modelGeneration) {
      await _closeModel(loadedModel);
      throw StateError('Inference model load was invalidated');
    }

    _model = loadedModel;
    return loadedModel;
  }

  /// Clears the cached model instance
  ///
  /// Call this when the active model changes (e.g., user switches models
  /// in settings) to ensure the next call to [getModel] retrieves the
  /// new active model.
  void clearCache() {
    unawaited(clearCacheAndWait());
  }

  /// Invalidates and releases the cached model, completing after all queued
  /// inference work has finished and the model has been closed.
  Future<void> clearCacheAndWait() {
    final cachedModel = _invalidateCachedModel();
    return _enqueue(
      cachedModel == null ? () async {} : () => _closeModel(cachedModel),
    );
  }

  /// Runs an operation on the same lane as model acquisition and release.
  /// The operation may call [clearCacheAndWaitInManagement] to release this
  /// provider without enqueuing behind itself.
  Future<T> runSerializedModelManagement<T>(Future<T> Function() action) {
    return _enqueue(action);
  }

  /// Releases the cached model while already inside
  /// [runSerializedModelManagement].
  Future<void> clearCacheAndWaitInManagement() {
    final cachedModel = _invalidateCachedModel();
    return cachedModel == null
        ? Future<void>.value()
        : _closeModel(cachedModel);
  }

  InferenceModel? _invalidateCachedModel() {
    final cachedModel = _model;
    _model = null;
    _inFlightFuture = null;
    _modelGeneration++;
    return cachedModel;
  }

  /// Releases the loaded model, used when the application is paused.
  Future<void> releaseModel() async {
    final cachedModel = _invalidateCachedModel();
    // Always enqueue a barrier. If a load is in flight, its generation check
    // closes the stale result before this release completes.
    await _enqueue(
      cachedModel == null ? () async {} : () => _closeModel(cachedModel),
    );
  }

  /// Runs one model-backed chat operation at a time.
  ///
  /// The plugin's legacy chat/session slot is mutable, so callers must use
  /// this lane even when their own work appears sequential. Each operation
  /// owns and closes its chat before the next operation starts.
  Future<T> runSerializedChat<T>(
    InferenceModel requestedModel, {
    required double temperature,
    required Future<T> Function(InferenceChat chat) action,
  }) {
    return _enqueue(() async {
      // A settings change can invalidate the model after getModel() returns
      // but before the caller reaches this lane. Reload inside the lane so a
      // queued operation never creates a chat on a model being closed.
      final model = identical(_model, requestedModel)
          ? requestedModel
          : await _loadModel(_modelGeneration);
      return _runSerializedChat(
        model,
        temperature: temperature,
        action: action,
      );
    });
  }

  /// Static compatibility seam for callers that only need serialization.
  /// Production services use [runSerializedChat] so cache invalidation can be
  /// checked at the point where the queued operation starts.
  static Future<T> withSerializedChat<T>(
    InferenceModel model, {
    required double temperature,
    required Future<T> Function(InferenceChat chat) action,
  }) {
    return _enqueue(
      () => _runSerializedChat(model, temperature: temperature, action: action),
    );
  }

  static Future<T> _runSerializedChat<T>(
    InferenceModel model, {
    required double temperature,
    required Future<T> Function(InferenceChat chat) action,
  }) async {
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
  }

  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _operationLane.then<T>((_) => action());
    _operationLane = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
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
