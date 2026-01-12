import 'dart:async';
import 'package:flutter_gemma/flutter_gemma.dart';

enum ModelStatus { notDownloaded, downloading, downloaded, error }

class ModelInfo {
  ModelInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    this.status = ModelStatus.notDownloaded,
    this.progress = 0.0,
  });
  final String id;
  final String name;
  final String url;
  final String type;
  ModelStatus status;
  double progress;
}

class ModelManagementService {
  final List<ModelInfo> _models = [
    ModelInfo(
      id: 'gemma-2b-it-gpu',
      name: 'Gemma 2B IT (GPU)',
      url:
          'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/gemma-2b-it-gpu-int4.bin',
      type: 'inference',
    ),
    ModelInfo(
      id: 'embedding-gemma',
      name: 'Embedding Gemma',
      url:
          'https://huggingface.co/google/embedding-gemma-7b-tflite/resolve/main/embedding_gemma_v1.bin', // Placeholder URL
      type: 'embedding',
    ),
  ];

  final _statusController = StreamController<List<ModelInfo>>.broadcast();
  Stream<List<ModelInfo>> get modelStatusStream => _statusController.stream;

  List<ModelInfo> get models => List.unmodifiable(_models);

  Future<void> initialize() async {
    for (final model in _models) {
      final filename = model.url.split('/').last;
      final isDownloaded = await FlutterGemma.isModelInstalled(filename);
      if (isDownloaded) {
        model
          ..status = ModelStatus.downloaded
          ..progress = 1.0;
      }
    }
    _notify();
  }

  Future<void> downloadModel(String modelId) async {
    final model = _models.firstWhere((m) => m.id == modelId);
    if (model.status == ModelStatus.downloading ||
        model.status == ModelStatus.downloaded) {
      return;
    }

    model
      ..status = ModelStatus.downloading
      ..progress = 0.0;
    _notify();

    try {
      if (model.type == 'inference') {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(model.url).withProgress((int progress) {
          model.progress = progress / 100.0;
          _notify();
        }).install();
      } else {
        await FlutterGemma.installEmbedder()
            .modelFromNetwork(model.url)
            .withModelProgress((int progress) {
              model.progress = progress / 100.0;
              _notify();
            })
            .install();
      }

      model
        ..status = ModelStatus.downloaded
        ..progress = 1.0;
    } on Exception catch (e) {
      model.status = ModelStatus.error;
      _statusController.addError('Download error: $e');
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
    _statusController.close();
  }
}
