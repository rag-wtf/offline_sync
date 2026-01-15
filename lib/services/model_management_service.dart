import 'dart:async';
import 'dart:developer';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/services/model_config.dart';

enum ModelStatus { notDownloaded, downloading, downloaded, error }

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

  String get effectiveFileName => fileName ?? url.split('/').last;
}

class ModelManagementService {
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

  Future<void> initialize() async {
    log('DEBUG: ModelManagementService.initialize() called');
    log('Initializing ModelManagementService');
    for (final model in _models) {
      log('DEBUG: Processing model ${model.id}');
      final filename = model.effectiveFileName;
      log('Checking if model ${model.id} ($filename) is installed...');

      var isDownloaded = false;
      try {
        log('DEBUG: Calling FlutterGemma.isModelInstalled for $filename');
        isDownloaded = await FlutterGemma.isModelInstalled(filename);
        log('DEBUG: FlutterGemma.isModelInstalled returned: $isDownloaded');
      } on Object catch (e) {
        log('Error checking model status for $filename: $e');
        log('DEBUG: Error checking model status: $e');
        // Assume not downloaded if check fails
      }

      log(
        'Model ${model.id} installed: $isDownloaded (Status: ${model.status})',
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
        model
          ..status = ModelStatus.downloaded
          ..progress = 1.0;

        // Only activate if this is set as active model
        if (model.type == AppModelType.embedding) {
          _activeEmbeddingModelId = model.id;
          await _activateEmbeddingModel(model);
        } else if (model.type == AppModelType.inference) {
          _activeInferenceModelId = model.id;
          await _activateInferenceModel(model);
        }
      }
      // Don't auto-download - let startup handle recommended model selection
    }
    log('DEBUG: initialize() completed, calling _notify()');
    _notify();
    log('DEBUG: initialize() fully completed');
  }

  Future<void> _activateEmbeddingModel(ModelInfo model) async {
    log('Activating embedding model ${model.id}');
    try {
      // Embedding model requires both model and tokenizer
      if (model.tokenizerUrl == null) {
        throw Exception(
          'Tokenizer URL is required for embedding model ${model.id}',
        );
      }
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(model.url)
          .tokenizerFromNetwork(model.tokenizerUrl!)
          .install();
      log('Embedding model activated');
    } on Exception catch (e) {
      log('Error activating embedding model: $e');
      model.status = ModelStatus.error;
      _statusController.addError('Activation error: $e');
    }
  }

  Future<void> _activateInferenceModel(ModelInfo model) async {
    log('Activating inference model ${model.id}');
    try {
      // Re-install/activate the inference model from the cached download
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
      ).fromNetwork(model.url).install();
      log('Inference model activated');
    } on Exception catch (e) {
      log('Error activating inference model: $e');
      model.status = ModelStatus.error;
      _statusController.addError('Activation error: $e');
    }
  }

  Future<void> downloadModel(String modelId) async {
    log('DEBUG: downloadModel called for $modelId');
    // If a download is already in progress for this model, wait for it.
    if (_activeDownloads.containsKey(modelId)) {
      log('Joining existing download for $modelId');
      log('DEBUG: Joining existing download for $modelId');
      return _activeDownloads[modelId];
    }

    final model = _models.firstWhere((m) => m.id == modelId);
    if (model.status == ModelStatus.downloaded) {
      log('Model $modelId already downloaded');
      log('DEBUG: Model $modelId already downloaded');
      return;
    }

    log('Starting download for $modelId from ${model.url}');
    log('DEBUG: Starting download for $modelId from ${model.url}');

    // Create and store the download future
    final downloadFuture = _performDownload(model);
    _activeDownloads[modelId] = downloadFuture;
    log('DEBUG: Added $modelId to _activeDownloads, now waiting...');

    try {
      await downloadFuture;
      log('DEBUG: downloadFuture completed for $modelId');
    } finally {
      unawaited(_activeDownloads.remove(modelId));
      log('DEBUG: Removed $modelId from _activeDownloads');
    }
  }

  Future<void> _performDownload(ModelInfo model) async {
    log('DEBUG: _performDownload started for ${model.id}');
    model
      ..status = ModelStatus.downloading
      ..progress = 0.0;
    _notify();

    try {
      final token = await AuthTokenService.loadToken();
      log('DEBUG: Token loaded for ${model.id}');
      final downloadUrl = model.url;

      if (token != null && token.isNotEmpty) {
        log('Using authentication token for download');
        log('DEBUG: Using authentication token');
      }

      log('DEBUG: About to call FlutterGemma install for ${model.id}');
      if (model.type == AppModelType.inference) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(downloadUrl, token: token).withProgress((int progress) {
          log('Download progress for ${model.id}: $progress%');
          model.progress = progress / 100.0;
          _notify();
        }).install();
      } else {
        // Embedding model requires both model and tokenizer
        if (model.tokenizerUrl == null) {
          throw Exception(
            'Tokenizer URL is required for embedding model ${model.id}',
          );
        }
        await FlutterGemma.installEmbedder()
            .modelFromNetwork(downloadUrl, token: token)
            .tokenizerFromNetwork(model.tokenizerUrl!, token: token)
            .withModelProgress((int progress) {
              log('Download progress for ${model.id}: $progress%');
              model.progress = progress / 100.0;
              _notify();
            })
            .install();
      }
      log('DEBUG: FlutterGemma install completed for ${model.id}');

      log('Download complete for ${model.id}');
      model
        ..status = ModelStatus.downloaded
        ..progress = 1.0;
      _notify();
      log('DEBUG: _performDownload fully completed for ${model.id}');
    } on Exception catch (e) {
      log('Download failed for ${model.id}: $e');
      log('DEBUG: Download failed for ${model.id}: $e');
      final errorMsg = e.toString();
      model.errorMessage = errorMsg;
      if (errorMsg.contains('401')) {
        model.status = ModelStatus.error;
        _statusController.addError(
          'Unauthorized (401). Please check your HF Token.',
        );
      } else {
        model.status = ModelStatus.error;
        _statusController.addError('Download error: $e');
      }
      _notify();
    }
  }

  Future<void> switchModel(String modelId) async {
    // In flutter_gemma, switching usually happens via installModel()
    // or by just ensuring it's available.
    // getActiveModel() retrieves the currently loaded one.
    // For RAG, we might need to load both.
  }

  void _notify() {
    _statusController.add(List.from(_models));
  }

  void dispose() {
    unawaited(_statusController.close());
  }
}
