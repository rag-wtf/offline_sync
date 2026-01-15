/// App-specific model type to avoid conflict with flutter_gemma's ModelType
enum AppModelType { embedding, inference }

/// Device tier for model selection
enum DeviceTier { low, mid, high, premium }

/// Centralized model configuration - single source of truth
/// for all model definitions used across the application.
class ModelConfig {
  /// All available models
  static List<ModelDefinition> get allModels => [
    ...InferenceModels.all,
    ...EmbeddingModels.all,
  ];
}

/// Inference models catalog
class InferenceModels {
  // Low tier: Gemma 3 270M (smallest, fastest)
  static const gemma3_270M = ModelDefinition(
    id: 'gemma3-270m',
    name: 'Gemma 3 270M IT',
    modelUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task',
    type: AppModelType.inference,
    sizeBytes: 300 * 1024 * 1024, // 300MB
    minRamMB: 600,
    requiresGpu: false,
    tier: DeviceTier.low,
  );

  // Mid tier: Gemma 3 1B
  static const gemma3_1B = ModelDefinition(
    id: 'gemma3-1b',
    name: 'Gemma 3 1B IT',
    modelUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    type: AppModelType.inference,
    sizeBytes: 500 * 1024 * 1024, // 500MB
    minRamMB: 1024,
    requiresGpu: false,
    tier: DeviceTier.mid,
  );

  // High tier: Gemma 3n E2B (multimodal)
  static const gemma3n_2B = ModelDefinition(
    id: 'gemma3n-e2b',
    name: 'Gemma 3 Nano E2B IT',
    modelUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    type: AppModelType.inference,
    sizeBytes: 3100 * 1024 * 1024, // 3.1GB
    minRamMB: 4096,
    requiresGpu: true,
    tier: DeviceTier.high,
  );

  // Premium tier: Gemma 3n E4B (multimodal, largest)
  static const gemma3n_4B = ModelDefinition(
    id: 'gemma3n-e4b',
    name: 'Gemma 3 Nano E4B IT',
    modelUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    type: AppModelType.inference,
    sizeBytes: 6500 * 1024 * 1024, // 6.5GB
    minRamMB: 8192,
    requiresGpu: true,
    tier: DeviceTier.premium,
  );

  static List<ModelDefinition> get all => [
    gemma3_270M,
    gemma3_1B,
    gemma3n_2B,
    gemma3n_4B,
  ];
}

/// Embedding models catalog
class EmbeddingModels {
  // Low tier: Gecko 64 (smallest, fastest)
  static const gecko64 = ModelDefinition(
    id: 'gecko-64',
    name: 'Gecko 64',
    modelUrl:
        'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_64_quant.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model',
    type: AppModelType.embedding,
    sizeBytes: 110 * 1024 * 1024, // 110MB
    minRamMB: 200,
    requiresGpu: false,
    tier: DeviceTier.low,
  );

  // Mid tier: EmbeddingGemma 256
  static const embeddingGemma256 = ModelDefinition(
    id: 'embedding-gemma-256',
    name: 'Embedding Gemma 256',
    modelUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    type: AppModelType.embedding,
    sizeBytes: 179 * 1024 * 1024, // 179MB
    minRamMB: 400,
    requiresGpu: false,
    tier: DeviceTier.mid,
  );

  // High tier: EmbeddingGemma 512
  static const embeddingGemma512 = ModelDefinition(
    id: 'embedding-gemma-512',
    name: 'Embedding Gemma 512',
    modelUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq512_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    type: AppModelType.embedding,
    sizeBytes: 179 * 1024 * 1024, // 179MB
    minRamMB: 400,
    requiresGpu: false,
    tier: DeviceTier.high,
  );

  // Premium tier: EmbeddingGemma 1024
  static const embeddingGemma1024 = ModelDefinition(
    id: 'embedding-gemma-1024',
    name: 'Embedding Gemma 1024',
    modelUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
    tokenizerUrl:
        'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    type: AppModelType.embedding,
    sizeBytes: 183 * 1024 * 1024, // 183MB
    minRamMB: 400,
    requiresGpu: false,
    tier: DeviceTier.premium,
  );

  static List<ModelDefinition> get all => [
    gecko64,
    embeddingGemma256,
    embeddingGemma512,
    embeddingGemma1024,
  ];
}

/// Model definition with all necessary metadata
class ModelDefinition {
  const ModelDefinition({
    required this.id,
    required this.name,
    required this.modelUrl,
    required this.type,
    required this.sizeBytes,
    required this.minRamMB,
    required this.requiresGpu,
    required this.tier,
    this.tokenizerUrl,
    this.sha256,
  });

  final String id;
  final String name;
  final String modelUrl;
  final String? tokenizerUrl;
  final AppModelType type;
  final int sizeBytes;
  final int minRamMB;
  final bool requiresGpu;
  final DeviceTier tier;
  final String? sha256; // For future checksum validation

  /// Get the expected filename from the URL
  String get fileName => modelUrl.split('/').last;

  /// Get human-readable size
  String get sizeFormatted {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)}KB';
    } else if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    } else {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
}
