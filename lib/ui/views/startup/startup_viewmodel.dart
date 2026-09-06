import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/l10n/gen/app_localizations_en.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/ui/setup_dialog_ui.dart';
import 'package:offline_sync/utils/download_failure.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

enum StartupStatus {
  downloading,
  downloadError,
  finalizing,
  authenticationRequired,
  detectingCapabilities,
  selectingModels,
  retrying,
}

void log(String message, {String? name}) {
  final safeMessage = LoggingService.redact(message);
  final isFailure = RegExp(
    'error|exception|failed|failure',
    caseSensitive: false,
  ).hasMatch(safeMessage);
  LoggingService.debug(
    isFailure ? 'Startup operation failed' : safeMessage,
    name: name,
  );
}

class StartupViewModel extends BaseViewModel {
  StartupViewModel({
    NavigationService? navigationService,
    DialogService? dialogService,
    ModelManagementService? modelService,
    DeviceCapabilityService? deviceService,
    ModelRecommendationService? recommendationService,
    DownloadPolicyService? downloadPolicyService,
    this._downloadConsentPrompter,
    this._ragSettingsService,
  }) : _navigationService = navigationService ?? locator<NavigationService>(),
       _dialogService = dialogService ?? locator<DialogService>(),
       _modelService = modelService ?? locator<ModelManagementService>(),
       _deviceService = deviceService ?? locator<DeviceCapabilityService>(),
       _recommendationService =
           recommendationService ?? locator<ModelRecommendationService>(),
       _downloadPolicyService =
           downloadPolicyService ?? locator<DownloadPolicyService>();

  final NavigationService _navigationService;
  final DialogService _dialogService;
  final ModelManagementService _modelService;
  final DeviceCapabilityService _deviceService;
  final ModelRecommendationService _recommendationService;
  final DownloadPolicyService _downloadPolicyService;
  final DownloadConsentPrompter? _downloadConsentPrompter;
  final RagSettingsService? _ragSettingsService;

  AppLocalizations get _localizations {
    try {
      final context = StackedService.navigatorKey?.currentContext;
      return context == null
          ? AppLocalizationsEn()
          : AppLocalizations.of(context);
    } on Object catch (_) {
      return AppLocalizationsEn();
    }
  }

  StreamSubscription<List<ModelInfo>>? _subscription;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;
  StartupStatus? _status;
  String? _statusModel;
  int? _statusProgress;

  String? localizedStatusMessage(
    AppLocalizations l10n,
  ) {
    switch (_status) {
      case StartupStatus.downloading:
        return _statusModel == null || _statusProgress == null
            ? l10n.initializingModels
            : l10n.downloadingModel(_statusModel!, _statusProgress!);
      case StartupStatus.downloadError:
        return l10n.downloadErrorStatus;
      case StartupStatus.finalizing:
        return l10n.finalizingInitialization;
      case StartupStatus.authenticationRequired:
        return l10n.authenticationRequiredStatus;
      case StartupStatus.detectingCapabilities:
        return l10n.detectingCapabilities;
      case StartupStatus.selectingModels:
        return l10n.selectingModels;
      case StartupStatus.retrying:
        return l10n.retryingStatus;
      case null:
        return null;
    }
  }

  void _setStatus(
    StartupStatus status, {
    String? model,
    int? progress,
    String? legacyMessage,
  }) {
    _status = status;
    _statusModel = model;
    _statusProgress = progress;
    _statusMessage = legacyMessage;
  }

  bool _needsToken = false;
  bool get needsToken => _needsToken;

  DeviceCapabilities? _capabilities;
  DeviceCapabilities? get capabilities => _capabilities;
  bool _isUnsupportedDevice = false;
  bool get isUnsupportedDevice => _isUnsupportedDevice;

  DownloadPolicyReason? _downloadPolicyReason;
  DownloadPolicyReason? get downloadPolicyReason => _downloadPolicyReason;

  // Track recommended model IDs for navigation check
  String? _recommendedInferenceModelId;
  String? _recommendedEmbeddingModelId;

  Future<void> runStartupLogic() async {
    LoggingService.debug('runStartupLogic called');
    log('runStartupLogic called', name: 'StartupViewModel');

    final previousSubscription = _subscription;
    if (previousSubscription != null) {
      await previousSubscription.cancel();
    }
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
          _setStatus(
            StartupStatus.downloading,
            model: m.name,
            progress: (m.progress * 100).round(),
            legacyMessage: 'Downloading ${m.name}: $progress%',
          );
          notifyListeners();
        } else {
          final error = models.where((m) => m.status == ModelStatus.error);
          if (error.isNotEmpty) {
            // Check if any of the errors indicate a 401 or auth requirement
            final failedAuthModel = error.where(_isAuthError).firstOrNull;

            if (failedAuthModel != null) {
              _setAuthError(failedAuthModel);
            } else {
              _setStatus(
                StartupStatus.downloadError,
                legacyMessage: 'Error downloading models.',
              );
              setError(_localizations.connectionOrStorageError);
            }
          } else {
            _setStatus(
              StartupStatus.finalizing,
              legacyMessage: 'Finalizing initialization...',
            );
            notifyListeners();
          }
        }
      },
      onError: (Object e) {
        if (e is AuthenticationRequiredException) {
          _needsToken = true;
          _setStatus(
            StartupStatus.authenticationRequired,
            legacyMessage: 'Authentication Required',
          );
          _setSafeError(e.message);
        } else if (isGatedAccessError(e)) {
          final failedAuthModel = _modelService.models
              .where(_isAuthError)
              .firstOrNull;
          final repo = failedAuthModel?.repoPage ?? 'https://huggingface.co';
          final description = describeDownloadFailure(e, repoPage: repo);
          _needsToken = true;
          _setStatus(
            StartupStatus.authenticationRequired,
            legacyMessage: 'Authentication Required',
          );
          _setSafeError(description);
        } else {
          _setSafeError(e);
        }
      },
    );

    try {
      // 1. Detect device capabilities
      _setStatus(
        StartupStatus.detectingCapabilities,
        legacyMessage: 'Detecting device capabilities...',
      );
      notifyListeners();
      _capabilities = await _deviceService.getCapabilities();
      log('Device capabilities: $_capabilities');

      // 2. Check minimum requirements
      if (!_recommendationService.meetsMinimumRequirements(_capabilities!)) {
        _isUnsupportedDevice = true;
        final message = _recommendationService.getUnsupportedDeviceMessage(
          _capabilities!,
          intro: _localizations.unsupportedDeviceIntro,
          ramMessage: _localizations.unsupportedDeviceRam,
          storageMessage: _localizations.unsupportedDeviceStorage,
        );
        setError(message);
        // For now, continue with smallest models anyway
        log('Device does not meet minimum requirements, using smallest models');
      }

      // 3. Get recommended models
      _setStatus(
        StartupStatus.selectingModels,
        legacyMessage: 'Selecting optimal models...',
      );
      notifyListeners();
      var recommended = _recommendationService.getRecommendedModels(
        _capabilities!,
      );
      log(
        'Recommended models: Inference=${recommended.inferenceModel.name}, '
        'Embedding=${recommended.embeddingModel.name}, '
        'Tier=${recommended.tier}',
      );

      // 4. Load persisted settings before model initialization restores the
      // selected native model identity.
      final ragSettings = _ragSettingsService ?? locator<RagSettingsService>();
      await ragSettings.initialize();
      log('RAG settings initialized', name: 'StartupViewModel');

      // 4.5. Initialize model service (checks existing models)
      LoggingService.debug('About to call _modelService.initialize()');
      log('About to call _modelService.initialize()', name: 'StartupViewModel');
      await _modelService.initialize();
      LoggingService.debug('_modelService.initialize() completed');
      log('_modelService.initialize() completed', name: 'StartupViewModel');

      // 5. Download recommended models if not present
      var inferenceModel = _modelService.models
          .where((m) => m.id == recommended.inferenceModel.id)
          .firstOrNull;
      var embeddingModel = _modelService.models
          .where((m) => m.id == recommended.embeddingModel.id)
          .firstOrNull;

      if (inferenceModel == null || embeddingModel == null) {
        log(
          'Recommended models not found in model service',
          name: 'StartupViewModel',
        );
        setError(_localizations.recommendedModelsUnavailable);
        return;
      }

      if (inferenceModel.status != ModelStatus.downloaded ||
          embeddingModel.status != ModelStatus.downloaded) {
        var modelsToDownload = <ModelDefinition>[
          if (inferenceModel.status != ModelStatus.downloaded)
            recommended.inferenceModel,
          if (embeddingModel.status != ModelStatus.downloaded)
            recommended.embeddingModel,
        ];
        final policy = await _downloadPolicyService.evaluate(
          modelsToDownload,
          _capabilities!,
        );
        if (!policy.allowed) {
          _setDownloadPolicyError(policy.reason);
          return;
        }
        if (policy.requiresConsent) {
          final consent = await _requestDownloadConsent(
            DownloadConsentRequest(
              modelsToDownload: modelsToDownload,
              smallerCompatible: _recommendationService
                  .getSmallerCompatibleModels(_capabilities!, recommended),
              reason: policy.reason,
            ),
          );
          if (!consent.approved) {
            _setDownloadPolicyError(DownloadPolicyReason.consentDenied);
            return;
          }
          if (consent.useSmallerCompatible) {
            final smaller = _recommendationService.getSmallerCompatibleModels(
              _capabilities!,
              recommended,
            );
            if (smaller != null) {
              recommended = smaller;
              inferenceModel = _modelService.models
                  .where((m) => m.id == recommended.inferenceModel.id)
                  .firstOrNull;
              embeddingModel = _modelService.models
                  .where((m) => m.id == recommended.embeddingModel.id)
                  .firstOrNull;
              if (inferenceModel == null || embeddingModel == null) {
                setError(_localizations.recommendedModelsUnavailable);
                return;
              }
              modelsToDownload = [
                if (inferenceModel.status != ModelStatus.downloaded)
                  recommended.inferenceModel,
                if (embeddingModel.status != ModelStatus.downloaded)
                  recommended.embeddingModel,
              ];
            }
          }
        }
      }

      // Store the final selected ids for the readiness/navigation check.
      _recommendedInferenceModelId = recommended.inferenceModel.id;
      _recommendedEmbeddingModelId = recommended.embeddingModel.id;

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
        final failedAuthModel = errors.where(_isAuthError).firstOrNull;
        if (failedAuthModel != null) {
          // coverage:ignore-start
          _setAuthError(failedAuthModel);
          // coverage:ignore-end
        } else if (!hasError) {
          setError(_localizations.modelDownloadFailed);
        }
        return;
      }

      await _checkAndNavigate();
    } on Object catch (e) {
      LoggingService.debug(
        'Exception in runStartupLogic: ${e.runtimeType}',
      );
      log(
        'Exception in runStartupLogic: ${e.runtimeType}',
        name: 'StartupViewModel',
      );
      _setSafeError(e);
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
    // coverage:ignore-start
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
    // coverage:ignore-end
  }

  Future<void> retry() async {
    setError(null);
    _downloadPolicyReason = null;
    _needsToken = false;
    _setStatus(StartupStatus.retrying, legacyMessage: 'Retrying...');
    notifyListeners();

    _modelService.resetErroredModels();

    await runStartupLogic();
  }

  void _setDownloadPolicyError(DownloadPolicyReason reason) {
    _downloadPolicyReason = reason;
    setError(reason.name);
  }

  Future<DownloadConsentResult> _requestDownloadConsent(
    DownloadConsentRequest request,
  ) async {
    final prompter = _downloadConsentPrompter;
    if (prompter != null) return prompter(request);
    final response = await _dialogService.showCustomDialog<dynamic, dynamic>(
      variant: DialogType.downloadConsent,
      data: DownloadConsentDialogData(request: request),
    );
    return DownloadConsentResult(
      approved: response?.confirmed ?? false,
      useSmallerCompatible: response?.data == true,
    );
  }

  void _setAuthError(ModelInfo model) {
    _needsToken = true;
    _setStatus(
      StartupStatus.authenticationRequired,
      legacyMessage: 'Authentication Required',
    );
    setError(
      LoggingService.redact(
        model.errorMessage ?? _localizations.missingHuggingFaceToken,
      ),
    );
  }

  void _setSafeError(Object error) {
    setError(LoggingService.redact(error.toString()));
  }

  String? get erroredModelRepoPage => _modelService.models
      .where((m) => m.status == ModelStatus.error && _hasGatedAccessError(m))
      .firstOrNull
      ?.repoPage;

  Future<void> enterToken() async {
    final erroredModel = _modelService.models
        .where((m) => m.status == ModelStatus.error && _isAuthError(m))
        .firstOrNull;

    await _dialogService.showCustomDialog<dynamic, dynamic>(
      variant: DialogType.tokenInput,
      data: TokenInputDialogData(
        repoPage: erroredModel?.hasGatedAccessError ?? false
            ? erroredModel?.repoPage
            : null,
        modelName: erroredModel?.name,
      ),
    );
    await retry();
  }

  bool _isAuthError(ModelInfo m) => m.isAuthError;

  bool _hasGatedAccessError(ModelInfo m) => m.hasGatedAccessError;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
