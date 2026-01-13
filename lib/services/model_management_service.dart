import 'dart:async';
import 'dart:developer';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/services/auth_token_service.dart';

enum ModelStatus { notDownloaded, downloading, downloaded, error }

class ModelInfo {
  ModelInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    this.fileName,
    this.status = ModelStatus.notDownloaded,
    this.progress = 0.0,
  });
  final String id;
  final String name;
  final String url;
  final String type;
  final String? fileName;
  ModelStatus status;
  double progress;
  String? errorMessage;

  String get effectiveFileName => fileName ?? url.split('/').last;
}

class ModelManagementService {
  final List<ModelInfo> _models = [
    ModelInfo(
      id: 'gemma-2b-it-gpu',
      name: 'Gemma 2B IT (GPU)',
      url:
          'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/gemma-2b-it-gpu-int4.bin',
      fileName: 'gemma-2b-it-gpu-int4.bin',
      type: 'inference',
    ),
    ModelInfo(
      id: 'embedding-gemma',
      name: 'Embedding Gemma',
      url:
          'https://huggingface.co/google/embedding-gemma-7b-tflite/resolve/main/embedding_gemma_v1.bin',
      fileName: 'embedding_gemma_v1.bin',
      type: 'embedding',
    ),
  ];

  final _statusController = StreamController<List<ModelInfo>>.broadcast();
  Stream<List<ModelInfo>> get modelStatusStream => _statusController.stream;

  List<ModelInfo> get models => List.unmodifiable(_models);

  Future<void> initialize() async {
    log('Initializing ModelManagementService');
    for (final model in _models) {
      final filename = model.effectiveFileName;
      log('Checking if model ${model.id} ($filename) is installed...');

      var isDownloaded = false;
      try {
        isDownloaded = await FlutterGemma.isModelInstalled(filename);
      } on Object catch (e) {
        log('Error checking model status for $filename: $e');
        // Assume not downloaded if check fails
      }

      log('Model ${model.id} installed: $isDownloaded');

      if (isDownloaded) {
        model
          ..status = ModelStatus.downloaded
          ..progress = 1.0;

        if (model.type == 'embedding') {
          await _activateEmbeddingModel(model);
        } else if (model.type == 'inference') {
          await _activateInferenceModel(model);
        }
      } else {
        // Auto-download models if missing
        if (model.type == 'embedding' || model.type == 'inference') {
          log('Auto-downloading model ${model.id}');
          await downloadModel(model.id);
        }
      }
    }
    _notify();
  }

  Future<void> _activateEmbeddingModel(ModelInfo model) async {
    log('Activating embedding model ${model.id}');
    try {
      // Just install/load without progress tracking since it's local
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(model.url)
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
    final model = _models.firstWhere((m) => m.id == modelId);
    if (model.status == ModelStatus.downloading ||
        model.status == ModelStatus.downloaded) {
      log('Model $modelId already downloading or downloaded');
      return;
    }

    log('Starting download for $modelId from ${model.url}');
    model
      ..status = ModelStatus.downloading
      ..progress = 0.0;
    _notify();

    try {
      final token = await AuthTokenService.loadToken();

      // Use clean URL without appended token
      final downloadUrl = model.url;

      if (token != null && token.isNotEmpty) {
        log('Using authentication token for download');
      }

      if (model.type == 'inference') {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(downloadUrl, token: token).withProgress((int progress) {
          log('Download progress for $modelId: $progress%');
          model.progress = progress / 100.0;
          _notify();
        }).install();
      } else {
        await FlutterGemma.installEmbedder()
            .modelFromNetwork(downloadUrl, token: token)
            .withModelProgress((int progress) {
              log('Download progress for $modelId: $progress%');
              model.progress = progress / 100.0;
              _notify();
            })
            .install();
      }

      log('Download complete for $modelId');
      model
        ..status = ModelStatus.downloaded
        ..progress = 1.0;
    } on Exception catch (e) {
      log('Download failed for $modelId: $e');
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
    }
    _notify();
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
