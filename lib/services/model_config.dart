/// App-specific model type to avoid conflict with flutter_gemma's ModelType
enum AppModelType {
  embedding,
  inference,
}

/// Centralized model configuration - single source of truth
/// for all model definitions used across the application.
class ModelConfig {
  /// Embedding model for generating vector embeddings
  static const embeddingModel = ModelDefinition(
    id: 'embedding-gemma',
    name: 'Embedding Gemma',
    modelUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/'
        'resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/'
        'resolve/main/sentencepiece.model',
    type: AppModelType.embedding,
    // TODO: Add actual SHA256 checksum from Hugging Face
    sha256: null,
  );

  /// Inference model for text generation
  static const inferenceModel = ModelDefinition(
    id: 'gemma-2b-it-gpu',
    name: 'Gemma 2B IT (GPU)',
    modelUrl:
        'https://huggingface.co/google/gemma-2b-it-tflite/'
        'resolve/main/gemma-2b-it-gpu-int4.bin',
    type: AppModelType.inference,
    // TODO: Add actual SHA256 checksum from Hugging Face
    sha256: null,
  );

  /// All available models
  static const List<ModelDefinition> allModels = [
    embeddingModel,
    inferenceModel,
  ];
}

/// Model definition with all necessary metadata
class ModelDefinition {
  const ModelDefinition({
    required this.id,
    required this.name,
    required this.modelUrl,
    required this.type,
    this.tokenizerUrl,
    this.sha256,
  });

  final String id;
  final String name;
  final String modelUrl;
  final String? tokenizerUrl;
  final AppModelType type;
  final String? sha256; // For future checksum validation

  /// Get the expected filename from the URL
  String get fileName => modelUrl.split('/').last;
}
