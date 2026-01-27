import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class StartupViewModel extends BaseViewModel {
  final NavigationService _navigationService = locator<NavigationService>();
  final ModelManagementService _modelService =
      locator<ModelManagementService>();
  final DeviceCapabilityService _deviceService = DeviceCapabilityService();
  final ModelRecommendationService _recommendationService =
      ModelRecommendationService();

  StreamSubscription<List<ModelInfo>>? _subscription;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  bool _needsToken = false;
  bool get needsToken => _needsToken;

  DeviceCapabilities? _capabilities;
  DeviceCapabilities? get capabilities => _capabilities;
  bool _isUnsupportedDevice = false;
  bool get isUnsupportedDevice => _isUnsupportedDevice;

  // Track recommended model IDs for navigation check
  String? _recommendedInferenceModelId;
  String? _recommendedEmbeddingModelId;

  Future<void> runStartupLogic() async {
    log('DEBUG: runStartupLogic called');
    log('runStartupLogic called', name: 'StartupViewModel');

    _subscription = _modelService.modelStatusStream.listen(
      (models) {
        final downloading = models.where(
          (m) => m.status == ModelStatus.downloading,
        );
        if (downloading.isNotEmpty) {
          final m = downloading.first;
          final progress = (m.progress * 100).toStringAsFixed(1);
          log(
            'Updating progress for ${m.name} to $progress% '
            '(raw: ${m.progress})',
            name: 'StartupViewModel',
          );
          _statusMessage = 'Downloading ${m.name}: $progress%';
          notifyListeners();
        } else {
          final error = models.where((m) => m.status == ModelStatus.error);
          if (error.isNotEmpty) {
            // Check if any of the errors indicate a 401
            final has401Error = error.any(
              (m) => m.errorMessage?.contains('401') ?? false,
            );

            if (has401Error) {
              _needsToken = true;
              _statusMessage = 'Authentication Required';
              setError('Missing or invalid Hugging Face Token.');
            } else {
              _statusMessage = 'Error downloading models.';
              setError('Check internet connection or storage.');
            }
          } else {
            _statusMessage = 'Finalizing initialization...';
            notifyListeners();
          }
        }
      },
      onError: (Object e) {
        final msg = e.toString();
        if (msg.contains('401')) {
          _needsToken = true;
          setError('Authentication Failed (401)');
        } else {
          setError(msg);
        }
      },
    );

    try {
      // 1. Detect device capabilities
      _statusMessage = 'Detecting device capabilities...';
      notifyListeners();
      _capabilities = await _deviceService.getCapabilities();
      log('Device capabilities: $_capabilities');

      // 2. Check minimum requirements
      if (!_recommendationService.meetsMinimumRequirements(_capabilities!)) {
        _isUnsupportedDevice = true;
        final message = _recommendationService.getUnsupportedDeviceMessage(
          _capabilities!,
        );
        setError(message);
        // For now, continue with smallest models anyway
        log('Device does not meet minimum requirements, using smallest models');
      }

      // 3. Get recommended models
      _statusMessage = 'Selecting optimal models...';
      notifyListeners();
      final recommended = _recommendationService.getRecommendedModels(
        _capabilities!,
      );
      log(
        'Recommended models: Inference=${recommended.inferenceModel.name}, '
        'Embedding=${recommended.embeddingModel.name}, '
        'Tier=${recommended.tier}',
      );

      // Store recommended model IDs for later navigation check
      _recommendedInferenceModelId = recommended.inferenceModel.id;
      _recommendedEmbeddingModelId = recommended.embeddingModel.id;

      // 4. Initialize model service (checks existing models)
      log('DEBUG: About to call _modelService.initialize()');
      log('About to call _modelService.initialize()', name: 'StartupViewModel');
      await _modelService.initialize();
      log('DEBUG: _modelService.initialize() completed');
      log('_modelService.initialize() completed', name: 'StartupViewModel');

      // 4.5. Initialize RAG settings service
      final ragSettings = locator<RagSettingsService>();
      await ragSettings.initialize();
      log('RAG settings initialized', name: 'StartupViewModel');

      // 5. Download recommended models if not present
      final inferenceModel = _modelService.models.firstWhere(
        (m) => m.id == recommended.inferenceModel.id,
      );
      final embeddingModel = _modelService.models.firstWhere(
        (m) => m.id == recommended.embeddingModel.id,
      );

      if (inferenceModel.status != ModelStatus.downloaded) {
        log('Downloading recommended inference model: ${inferenceModel.name}');
        await _modelService.downloadModel(inferenceModel.id);
      }

      if (embeddingModel.status != ModelStatus.downloaded) {
        log('Downloading recommended embedding model: ${embeddingModel.name}');
        await _modelService.downloadModel(embeddingModel.id);
      }

      // Ensure they are active (Critically important for Web where initialize()
      // skipped it)
      if (_modelService.activeInferenceModel == null &&
          inferenceModel.status == ModelStatus.downloaded) {
        log('Activating recommended inference model: ${inferenceModel.name}');
        await _modelService.switchInferenceModel(inferenceModel.id);
      }

      if (_modelService.activeEmbeddingModel == null &&
          embeddingModel.status == ModelStatus.downloaded) {
        log('Activating recommended embedding model: ${embeddingModel.name}');
        await _modelService.switchEmbeddingModel(embeddingModel.id);
      }

      // Check if any critical errors occurred during downloads
      final errors = _modelService.models.where(
        (m) => m.status == ModelStatus.error,
      );
      if (errors.isNotEmpty) {
        if (errors.any((m) => m.errorMessage?.contains('401') ?? false)) {
          _needsToken = true;
          setError('Missing or invalid Hugging Face Token.');
        } else if (!hasError) {
          setError('Failed to download models. Please retry.');
        }
        return;
      }

      await _checkAndNavigate();
    } on Object catch (e) {
      log('DEBUG: Exception in runStartupLogic: $e');
      log('Exception in runStartupLogic: $e', name: 'StartupViewModel');
      setError(e.toString());
    }
  }

  Future<void> _checkAndNavigate() async {
    // Check the status of the recommended models that were downloaded
    final inferenceModel = _modelService.models.firstWhere(
      (m) => m.id == _recommendedInferenceModelId,
    );
    final embeddingModel = _modelService.models.firstWhere(
      (m) => m.id == _recommendedEmbeddingModelId,
    );

    log(
      'Checking models for navigation: '
      '''Inference: ${inferenceModel.status}, Embedding: ${embeddingModel.status}''',
      name: 'StartupViewModel',
    );

    // On Web, checking persistence via isModelInstalled is unreliable.
    // If we have reached this point without errors, and we attempted
    // to download (which loads the model on Web), we should proceed.
    // We check for 'downloaded' OR if we are on Web and just finished
    // 'downloading'.
    if ((inferenceModel.status == ModelStatus.downloaded &&
            embeddingModel.status == ModelStatus.downloaded) ||
        (kIsWeb && !hasError)) {
      log(
        'Models ready (or Web load complete). Navigating to ChatView.',
        name: 'StartupViewModel',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _navigationService.replaceWithChatView();
    } else {
      log(
        'Models not ready. Navigating to SettingsView.',
        name: 'StartupViewModel',
      );
      // If we are here after initialize() with no errors,
      // it theoretically shouldn't happen if we auto-downloaded everything.
      // But if something is missing, go to settings.
      await _navigationService.replaceWithSettingsView();
    }
  }

  Future<void> retry() async {
    setError(null);
    _needsToken = false;
    _statusMessage = 'Retrying...';
    notifyListeners();

    // Reset any models that are in error state back to notDownloaded
    // so they can be retried
    for (final model in _modelService.models) {
      if (model.status == ModelStatus.error) {
        model
          ..status = ModelStatus.notDownloaded
          ..progress = 0.0
          ..errorMessage = null;
      }
    }

    await runStartupLogic();
  }

  Future<void> enterToken() async {
    await _navigationService.navigateWithTransition<bool?>(
      const TokenInputDialog(),
      transitionStyle: Transition.fade,
    );
    await retry();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
