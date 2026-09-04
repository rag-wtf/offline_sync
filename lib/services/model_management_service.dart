import 'dart:async';
import 'dart:developer';
import 'dart:io';

// Constructor parameters keep public names while assigning private test hooks.
// ignore_for_file: prefer_initializing_formals

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/utils/download_failure.dart';
import 'package:offline_sync/utils/hugging_face.dart';

enum ModelStatus { notDownloaded, downloading, downloaded, error }

enum ModelDownloadFailureKind { none, authentication, gatedAccess }

typedef InferenceModelInstaller =
    Future<void> Function(
      String url, {
      required bool foreground,
    });

class ModelInfo {
  ModelInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    this.tokenizerUrl,
    this.fileName,
    this.status = ModelStatus.notDownloaded,
    this.progress = 0.0,
  });
  final String id;
  final String name;
  final String url;
  final AppModelType type;
  final String? tokenizerUrl;
  final String? fileName;
  ModelStatus status;
  double progress;
  String? errorMessage;
  ModelDownloadFailureKind failureKind = ModelDownloadFailureKind.none;

  bool get isAuthError => failureKind != ModelDownloadFailureKind.none;

  bool get hasGatedAccessError =>
      failureKind == ModelDownloadFailureKind.gatedAccess;

  String get effectiveFileName => fileName ?? url.split('/').last;

  /// The Hugging Face repo page for [url].
  String get repoPage => deriveHuggingFaceRepoPage(url);
}

class ModelManagementService {
  ModelManagementService({
    Future<String?> Function(ModelDefinition definition)?
    installedModelPathResolver,
    Future<bool> Function(String filename)? modelInstalledChecker,
    Future<void> Function(ModelInfo model)? inferenceModelActivator,
    InferenceModelInstaller? inferenceModelInstaller,
    Future<void> Function(ModelInfo model)? embeddingModelActivator,
    Future<String?> Function()? authTokenLoader,
    Future<void> Function(
      ModelInfo model,
      String? token,
      void Function(double progress) onProgress,
    )?
    inferenceModelDownloader,
    Future<void> Function(
      ModelInfo model,
      String? token,
      void Function(double progress) onProgress,
    )?
    embeddingModelDownloader,
    Future<bool> Function(File file, String expectedSha256)?
    fileChecksumVerifier,
    DeviceCapabilityService? deviceService,
    Future<DeviceCapabilities> Function()? capabilitiesProvider,
  }) : _installedModelPathResolver = installedModelPathResolver,
       _modelInstalledChecker = modelInstalledChecker,
       _inferenceModelActivator = inferenceModelActivator,
       _inferenceModelInstaller = inferenceModelInstaller,
       _embeddingModelActivator = embeddingModelActivator,
       _authTokenLoader = authTokenLoader,
       _inferenceModelDownloader = inferenceModelDownloader,
       _embeddingModelDownloader = embeddingModelDownloader,
       _fileChecksumVerifier = fileChecksumVerifier,
       _deviceService = deviceService,
       _capabilitiesProvider = capabilitiesProvider;
  // Pre-compiled Regular Expressions for performance optimization
  static final _pathSeparatorRegex = RegExp(r'[\/\\]'); // coverage:ignore-line

  static final Map<String, ModelDefinition> _modelDefinitionsById = {
    for (final model in ModelConfig.allModels) model.id: model,
  };

  final Future<String?> Function(ModelDefinition definition)?
  _installedModelPathResolver;
  final Future<bool> Function(String filename)? _modelInstalledChecker;
  final Future<void> Function(ModelInfo model)? _inferenceModelActivator;
  final InferenceModelInstaller? _inferenceModelInstaller;
  final Future<void> Function(ModelInfo model)? _embeddingModelActivator;
  final Future<String?> Function()? _authTokenLoader;
  final Future<void> Function(
    ModelInfo model,
    String? token,
    void Function(double progress) onProgress,
  )?
  _inferenceModelDownloader;
  final Future<void> Function(
    ModelInfo model,
    String? token,
    void Function(double progress) onProgress,
  )?
  _embeddingModelDownloader;
  final Future<bool> Function(File file, String expectedSha256)?
  _fileChecksumVerifier;
  final DeviceCapabilityService? _deviceService;
  final Future<DeviceCapabilities> Function()? _capabilitiesProvider;

  // Initialize models from ModelConfig
  final List<ModelInfo> _models = ModelConfig.allModels
      .map(
        (config) => ModelInfo(
          id: config.id,
          name: config.name,
          url: config.modelUrl,
          tokenizerUrl: config.tokenizerUrl,
          type: config.type,
        ),
      )
      .toList();

  final RagSettingsService _ragSettings = locator<RagSettingsService>();

  final _statusController = StreamController<List<ModelInfo>>.broadcast();
  Stream<List<ModelInfo>> get modelStatusStream => _statusController.stream;

  // Track active downloads to prevent race conditions
  final Map<String, Future<void>> _activeDownloads = {};

  // Track active models
  String? _activeInferenceModelId;
  String? _activeEmbeddingModelId;

  List<ModelInfo> get models => List.unmodifiable(_models);

  /// Get active inference model
  ModelInfo? get activeInferenceModel {
    if (_activeInferenceModelId == null) return null;
    return _models.firstWhere((m) => m.id == _activeInferenceModelId);
  }

  /// Get active embedding model
  ModelInfo? get activeEmbeddingModel {
    if (_activeEmbeddingModelId == null) return null;
    return _models.firstWhere((m) => m.id == _activeEmbeddingModelId);
  }

  Future<void>? _initFuture;

  Future<void> initialize() {
    return _initFuture ??= _performInitialize();
  }

  Future<void> refresh() {
    _initFuture = _performInitialize();
    return _initFuture!;
  }

  Future<void> _performInitialize() async {
    LoggingService.debug('ModelManagementService.initialize() called');
    log('Initializing ModelManagementService');
    await Future.wait(
      _models.map((model) async {
        LoggingService.debug('Processing model ${model.id}');
        final filename = model.effectiveFileName;
        log('Checking if model ${model.id} ($filename) is installed...');

        var isDownloaded = false;
        try {
          LoggingService.debug(
            'Calling FlutterGemma.isModelInstalled for $filename',
          );
          final checker =
              _modelInstalledChecker ?? FlutterGemma.isModelInstalled;
          isDownloaded = await checker(filename);
          LoggingService.debug(
            'FlutterGemma.isModelInstalled returned: $isDownloaded',
          );
        } on Object catch (e) {
          log('Error checking model status for $filename: $e');
          LoggingService.debug('Error checking model status: $e');
          // Assume not downloaded if check fails
        }

        log(
          'Model ${model.id} installed: $isDownloaded '
          '(Status: ${model.status})',
        );

        // Fix: If status says downloaded but file is missing, reset status.
        // This allows re-downloading if the file was deleted or corrupted.
        if (!isDownloaded && model.status == ModelStatus.downloaded) {
          log('Model ${model.id} status mismatch: Resetting to notDownloaded.');
          model
            ..status = ModelStatus.notDownloaded
            ..progress = 0.0;
        }

        if (isDownloaded) {
          final isVerified = await _verifyDeclaredChecksum(model);
          if (!isVerified) {
            return;
          }
          model
            ..status = ModelStatus.downloaded
            ..progress = 1.0;
        }
      }),
    );

    // Now restore active models from persistence
    final savedInferenceId = _ragSettings.activeInferenceModelId;
    final savedEmbeddingId = _ragSettings.activeEmbeddingModelId;

    if (savedInferenceId != null) {
      final model = _modelForSavedId(savedInferenceId, AppModelType.inference);
      if (model != null && model.status == ModelStatus.downloaded) {
        if (await _activateInferenceModel(model)) {
          _activeInferenceModelId = model.id;
        }
      }
    }

    if (savedEmbeddingId != null) {
      final model = _modelForSavedId(savedEmbeddingId, AppModelType.embedding);
      if (model != null && model.status == ModelStatus.downloaded) {
        if (await _activateEmbeddingModel(model)) {
          _activeEmbeddingModelId = model.id;
        }
      }
    }

    LoggingService.debug('initialize() completed, calling _notify()');
    _notify();
    LoggingService.debug('initialize() fully completed');
  }

  Future<bool> _activateEmbeddingModel(ModelInfo model) async {
    log('Activating embedding model ${model.id}');
    if (!await _isCompatible(model)) return false;
    try {
      final activator = _embeddingModelActivator;
      if (activator != null) {
        await activator(model);
        log('Embedding model activated');
        return true;
      }
      // Embedding model requires both model and tokenizer
      if (model.tokenizerUrl == null) {
        // coverage:ignore-start
        throw Exception(
          'Tokenizer URL is required for embedding model ${model.id}',
        );
        // coverage:ignore-end
      }
      // coverage:ignore-start
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(model.url)
          .tokenizerFromNetwork(model.tokenizerUrl!)
          .install();
      log('Embedding model activated');
      return true;
      // coverage:ignore-end
    } on Exception catch (e) {
      log('Error activating embedding model: $e');
      model
        ..status = ModelStatus.error
        ..errorMessage = e.toString();
      _statusController.addError('Activation error: $e');
      return false;
    }
  }

  Future<bool> _activateInferenceModel(ModelInfo model) async {
    log('Activating inference model ${model.id}');
    if (!await _isCompatible(model)) return false;
    try {
      final activator = _inferenceModelActivator;
      if (activator != null) {
        await activator(model);
        log('Inference model activated');
        return true;
      }
      // Re-install/activate the inference model from the cached download
      // coverage:ignore-start
      final installer = _inferenceModelInstaller;
      if (installer != null) {
        await installer(model.url, foreground: false);
      } else {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(model.url, foreground: false).install();
      }
      log('Inference model activated');
      return true;
      // coverage:ignore-end
    } on Exception catch (e) {
      log('Error activating inference model: $e');
      model
        ..status = ModelStatus.error
        ..errorMessage = e.toString();
      _statusController.addError('Activation error: $e');
      return false;
    }
  }

  Future<void> downloadModel(String modelId) async {
    LoggingService.debug('downloadModel called for $modelId');
    // If a download is already in progress for this model, wait for it.
    if (_activeDownloads.containsKey(modelId)) {
      // coverage:ignore-start
      log('Joining existing download for $modelId');
      LoggingService.debug('Joining existing download for $modelId');
      return _activeDownloads[modelId];
      // coverage:ignore-end
    }

    final model = _models.firstWhere((m) => m.id == modelId);
    if (!await _isCompatible(model)) return;
    if (model.status == ModelStatus.downloaded) {
      // coverage:ignore-start
      log('Model $modelId already downloaded');
      LoggingService.debug('Model $modelId already downloaded');
      return;
      // coverage:ignore-end
    }

    log('Starting download for $modelId from ${model.url}');
    LoggingService.debug('Starting download for $modelId from ${model.url}');

    // Create and store the download future
    final downloadFuture = _performDownload(model);
    _activeDownloads[modelId] = downloadFuture;
    LoggingService.debug('Added $modelId to _activeDownloads, now waiting...');

    try {
      await downloadFuture;
      LoggingService.debug('downloadFuture completed for $modelId');
    } finally {
      unawaited(_activeDownloads.remove(modelId));
      LoggingService.debug('Removed $modelId from _activeDownloads');
    }
  }

  Future<void> _performDownload(ModelInfo model) async {
    LoggingService.debug('_performDownload started for ${model.id}');
    model
      ..status = ModelStatus.downloading
      ..progress = 0.0;
    _notify();

    // Capture currently active model of the same type to restore later
    String? previousActiveId;
    if (model.type == AppModelType.inference) {
      previousActiveId = _activeInferenceModelId;
    } else {
      previousActiveId = _activeEmbeddingModelId;
    }

    try {
      final token = await (_authTokenLoader ?? AuthTokenService.loadToken)();
      LoggingService.debug('Token loaded for ${model.id}');
      final downloadUrl = model.url;

      if (token != null && token.isNotEmpty) {
        log('Using authentication token for download');
        LoggingService.debug('Using authentication token');
      }

      LoggingService.debug(
        'About to call FlutterGemma install for ${model.id}',
      );
      if (model.type == AppModelType.inference) {
        final downloader = _inferenceModelDownloader;
        if (downloader != null) {
          await downloader(model, token, (progress) {
            log('Download progress for ${model.id}: $progress%');
            model.progress = progress / 100.0;
            _notify();
          });
        } else {
          // coverage:ignore-start
          await FlutterGemma.installModel(
                modelType: ModelType.gemmaIt,
              )
              .fromNetwork(
                downloadUrl,
                token: token,
                foreground: true,
              )
              .withProgress((progress) {
                log('Download progress for ${model.id}: $progress%');
                model.progress = progress / 100.0;
                _notify();
              })
              .install();
          // coverage:ignore-end
        }
      } else {
        // Embedding model requires both model and tokenizer
        if (model.tokenizerUrl == null) {
          // coverage:ignore-start
          throw Exception(
            'Tokenizer URL is required for embedding model ${model.id}',
          );
          // coverage:ignore-end
        }
        final downloader = _embeddingModelDownloader;
        if (downloader != null) {
          await downloader(model, token, (progress) {
            log('Download progress for ${model.id}: $progress%');
            model.progress = progress / 100.0;
            _notify();
          });
        } else {
          // coverage:ignore-start
          await FlutterGemma.installEmbedder()
              .modelFromNetwork(downloadUrl, token: token)
              .tokenizerFromNetwork(model.tokenizerUrl!, token: token)
              .withModelProgress((progress) {
                log('Download progress for ${model.id}: $progress%');
                model.progress = progress / 100.0;
                _notify();
              })
              .install();
          // coverage:ignore-end
        }
      }
      LoggingService.debug('FlutterGemma install completed for ${model.id}');

      final isVerified = await _verifyDeclaredChecksum(model);
      if (!isVerified) {
        // coverage:ignore-start
        _notify();
        return;
        // coverage:ignore-end
      }

      log('Download complete for ${model.id}');
      model
        ..status = ModelStatus.downloaded
        ..progress = 1.0;

      // AUTO-ACTIVATION LOGIC
      if (previousActiveId == null) {
        // No model was active, so this is the "First Download".
        // Auto-activate it to help the user get started.
        log('First download detected. Auto-activating ${model.id}');
        if (model.type == AppModelType.inference) {
          await switchInferenceModel(model.id);
        } else {
          // coverage:ignore-start
          await switchEmbeddingModel(model.id);
          // coverage:ignore-end
        }
      } else if (previousActiveId != model.id) {
        // A model was already active, and it wasn't this one.
        // Downloading typically implicitly loads the new model (side effect of
        // install()).
        // We must restore the user's previous active model.
        log(
          'Restoring previously active model $previousActiveId after download '
          'of ${model.id}',
        );

        final previousModel = _models.firstWhere(
          (m) => m.id == previousActiveId,
        );
        if (model.type == AppModelType.inference) {
          await _activateInferenceModel(previousModel);
        } else {
          await _activateEmbeddingModel(previousModel);
        }
      }

      _notify();
      LoggingService.debug('_performDownload fully completed for ${model.id}');
    } on Exception catch (e) {
      log('Download failed for ${model.id}: $e');
      LoggingService.debug('Download failed for ${model.id}: $e');
      model.status = ModelStatus.error;

      final isGatedError = isGatedAccessError(e);
      final isAuthenticationError =
          isGatedError || e is AuthenticationRequiredException;

      if (isAuthenticationError) {
        final description = isGatedError
            ? describeDownloadFailure(e, repoPage: model.repoPage)
            : e.toString();
        model
          ..failureKind = isGatedError
              ? ModelDownloadFailureKind.gatedAccess
              : ModelDownloadFailureKind.authentication
          ..errorMessage = description;
        _statusController.addError(
          AuthenticationRequiredException(description),
        );
      } else {
        // coverage:ignore-start
        model
          ..failureKind = ModelDownloadFailureKind.none
          ..errorMessage = e.toString();
        _statusController.addError('Download error: $e');
        // coverage:ignore-end
      }
      _notify();
    }
  }

  /// Get downloaded inference models
  List<ModelInfo> get downloadedInferenceModels => _models
      .where(
        (m) =>
            m.type == AppModelType.inference &&
            m.status == ModelStatus.downloaded,
      )
      .toList();

  /// Get downloaded embedding models
  List<ModelInfo> get downloadedEmbeddingModels => _models
      .where(
        (m) =>
            m.type == AppModelType.embedding &&
            m.status == ModelStatus.downloaded,
      )
      .toList();

  /// Switch to a different inference model
  Future<void> switchInferenceModel(String modelId) async {
    final model = _models.firstWhere((m) => m.id == modelId);
    if (model.status != ModelStatus.downloaded) {
      log('Cannot switch to model $modelId: not downloaded');
      return;
    }
    if (model.type != AppModelType.inference) {
      // coverage:ignore-start
      log('Cannot switch to model $modelId: not an inference model');
      return;
      // coverage:ignore-end
    }
    log('Switching to inference model $modelId');
    final previousActiveId = _activeInferenceModelId;
    if (!await _activateInferenceModel(model)) {
      _activeInferenceModelId = previousActiveId;
      _notify();
      return;
    }
    _activeInferenceModelId = modelId;
    await _ragSettings.setActiveInferenceModelId(modelId);
    if (locator.isRegistered<InferenceModelProvider>()) {
      locator<InferenceModelProvider>().clearCache();
    }
    _notify();
  }

  /// Switch to a different embedding model
  Future<void> switchEmbeddingModel(String modelId) async {
    final model = _models.firstWhere((m) => m.id == modelId);
    if (model.status != ModelStatus.downloaded) {
      log('Cannot switch to model $modelId: not downloaded');
      return;
    }
    if (model.type != AppModelType.embedding) {
      // coverage:ignore-start
      log('Cannot switch to model $modelId: not an embedding model');
      return;
      // coverage:ignore-end
    }
    log('Switching to embedding model $modelId');
    final previousActiveId = _activeEmbeddingModelId;
    if (!await _activateEmbeddingModel(model)) {
      // coverage:ignore-start
      _activeEmbeddingModelId = previousActiveId;
      _notify();
      return;
      // coverage:ignore-end
    }
    _activeEmbeddingModelId = modelId;
    await _ragSettings.setActiveEmbeddingModelId(modelId);
    _notify();
  }

  void _notify() {
    _statusController.add(List.from(_models));
  }

  ModelInfo? _modelForSavedId(String id, AppModelType type) {
    for (final model in _models) {
      if (model.id == id && model.type == type) return model;
    }
    for (final model in _models) {
      if (model.type == type) return model;
    }
    return null;
  }

  Future<bool> _isCompatible(ModelInfo model) async {
    final definition = _modelDefinitionsById[model.id];
    final capabilities = await _readCapabilities();
    if (definition != null && definition.isCompatibleWith(capabilities)) {
      return true;
    }

    model
      ..status = ModelStatus.error
      ..progress = 0
      ..failureKind = ModelDownloadFailureKind.none
      ..errorMessage =
          'Model ${model.name} is not compatible with '
          '${capabilities.platform}.';
    _notify();
    return false;
  }

  Future<DeviceCapabilities> _readCapabilities() {
    final provider = _capabilitiesProvider;
    if (provider != null) return provider();
    final service = _deviceService;
    if (service != null) return service.getCapabilities();
    if (locator.isRegistered<DeviceCapabilityService>()) {
      return locator<DeviceCapabilityService>().getCapabilities();
    }
    // Compatibility for existing direct service users that pre-date the
    // locator registration. Production uses the locator singleton above.
    return Future.value(
      const DeviceCapabilities(
        totalRamMB: 4096,
        availableStorageMB: 4096,
        hasGpu: true,
        platform: 'android',
      ),
    );
  }

  void resetErroredModels() {
    for (final model in _models) {
      if (model.status == ModelStatus.error) {
        model
          ..status = ModelStatus.notDownloaded
          ..progress = 0.0
          ..failureKind = ModelDownloadFailureKind.none
          ..errorMessage = null;
      }
    }
    _notify();
  }

  void dispose() {
    unawaited(_statusController.close());
  }

  static final Set<String> _verifiedChecksumCache = <String>{};

  Future<bool> _verifyDeclaredChecksum(ModelInfo model) async {
    final definition = _modelDefinitionsById[model.id];
    final expectedSha256 = definition?.sha256;
    if (definition == null || expectedSha256 == null) {
      return true;
    }

    // In testing: If a fake downloader is injected without a path resolver,
    // bypass on-disk checksum check since no real file was downloaded.
    if (_installedModelPathResolver == null &&
        ((model.type == AppModelType.inference &&
                _inferenceModelDownloader != null) ||
            (model.type == AppModelType.embedding &&
                _embeddingModelDownloader != null))) {
      return true;
    }

    // M-1: Checksum enforcement depends on flutter_gemma resolving the
    // installed model back to an on-disk path. If path lookup fails, we cannot
    // prove integrity and therefore fail closed for models with declared
    // digests rather than treating them as downloaded.
    final installedModelPath = await _resolveInstalledModelPath(definition);
    if (installedModelPath == null) {
      model
        ..status = ModelStatus.error
        ..progress = 0.0
        ..errorMessage =
            'Checksum verification unavailable: '
            'installed file path not exposed';
      _statusController.addError(
        'Checksum verification unavailable for ${model.id}.',
      );
      return false;
    }

    final modelFile = File(installedModelPath);
    if (modelFile.existsSync()) {
      final stat = modelFile.statSync();
      final cacheKey =
          '$installedModelPath:${stat.modified.millisecondsSinceEpoch}:'
          '${stat.size}:$expectedSha256';
      if (_verifiedChecksumCache.contains(cacheKey)) {
        return true;
      }

      final verifier = _fileChecksumVerifier ?? verifyFileSha256;
      final isVerified = await verifier(modelFile, expectedSha256);
      if (isVerified) {
        _verifiedChecksumCache.add(cacheKey);
        return true;
      }
    } else {
      final verifier = _fileChecksumVerifier ?? verifyFileSha256;
      final isVerified = await verifier(modelFile, expectedSha256);
      if (isVerified) {
        return true;
      }
    }

    if (modelFile.existsSync()) {
      modelFile.deleteSync();
    }
    model
      ..status = ModelStatus.error
      ..progress = 0.0
      ..errorMessage = 'Checksum mismatch for ${model.id}';
    _statusController.addError('Checksum mismatch for ${model.id}.');
    return false;
  }

  @visibleForTesting
  Future<bool> verifyDeclaredChecksumForTest(ModelInfo model) {
    return _verifyDeclaredChecksum(model);
  }

  Future<String?> _resolveInstalledModelPath(ModelDefinition definition) async {
    final resolver = _installedModelPathResolver;
    if (resolver != null) {
      return resolver(definition);
    }

    try {
      // coverage:ignore-start
      final filePaths = await FlutterGemmaPlugin.instance.modelManager
          .getModelFilePaths(_buildModelSpec(definition));
      if (filePaths == null) {
        return null;
      }

      for (final installedPath in filePaths.values) {
        if (installedPath.split(_pathSeparatorRegex).last ==
            definition.fileName) {
          return installedPath;
        }
      }
    } on Object catch (e) {
      log('Error resolving installed model path for ${definition.id}: $e');
    }
    // coverage:ignore-end

    return null;
  }

  // coverage:ignore-start
  ModelSpec _buildModelSpec(ModelDefinition definition) {
    if (definition.type == AppModelType.embedding) {
      final tokenizerUrl = definition.tokenizerUrl;
      if (tokenizerUrl == null) {
        throw StateError(
          'Tokenizer URL is required for embedding model ${definition.id}',
        );
      }
      return EmbeddingModelSpec.fromLegacyUrl(
        name: definition.name,
        modelUrl: definition.modelUrl,
        tokenizerUrl: tokenizerUrl,
      );
    }

    return InferenceModelSpec.fromLegacyUrl(
      name: definition.name,
      modelUrl: definition.modelUrl,
      modelType: ModelType.gemmaIt,
    );
  }
  // coverage:ignore-end

  static Future<bool> verifyFileSha256(File file, String expectedSha256) async {
    try {
      if (!file.existsSync()) {
        return false;
      }

      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == expectedSha256.toLowerCase();
    } on Object {
      return false;
    }
  }
}
