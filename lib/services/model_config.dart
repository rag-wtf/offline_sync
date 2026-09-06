import 'package:flutter_gemma/flutter_gemma.dart' show ModelFileType;
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/utils/hugging_face.dart';

export 'package:flutter_gemma/flutter_gemma.dart' show ModelFileType;

/// App-specific model type to avoid conflict with flutter_gemma's ModelType
enum AppModelType { embedding, inference }

/// Device tier for model selection
enum DeviceTier { low, mid, high, premium }

/// Platform runtime that has a registered model engine.
enum ModelPlatform { web, android, ios, linux, macos, windows }

enum ModelDigestSource { declared, huggingFaceLfs }

extension ModelPlatformParsing on ModelPlatform {
  static ModelPlatform? fromDevicePlatform(String platform) {
    for (final value in ModelPlatform.values) {
      if (value.name == platform) return value;
    }
    return null;
  }
}

/// Centralized model configuration - single source of truth
/// for all model definitions used across the application.
class ModelConfig {
  /// All available models
  static List<ModelDefinition> get allModels => [
    ...InferenceModels.all,
    ...EmbeddingModels.all,
  ];

  static ModelDefinition activeInferenceModelOrDefault(
    String? activeInferenceModelId,
  ) {
    if (activeInferenceModelId != null) {
      for (final model in InferenceModels.all) {
        if (model.id == activeInferenceModelId) {
          return model;
        }
      }
    }

    return InferenceModels.gemma3_270M;
  }

  static int activeInferenceContextLimit(String? activeInferenceModelId) {
    final model = activeInferenceModelOrDefault(activeInferenceModelId);
    return model.contextLimit ?? model.maxTokens;
  }
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
    maxTokens: 1024, // Conservative for low-end devices
    contextLimit: 1024,
    sha256: '0f7147f1c22eaf758b819bbf7841793e4c90096c9352cde7fbe5c631f2265ef5',
    fileType: ModelFileType.task,
    supportedPlatforms: {
      ModelPlatform.web,
      ModelPlatform.android,
      ModelPlatform.ios,
    },
  );

  // Mid tier: Gemma 3 1B
  static const gemma3_1B = ModelDefinition(
    id: 'gemma3-1b',
    name: 'Gemma 3 1B IT',
    modelUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    type: AppModelType.inference,
    sizeBytes: 584417280,
    minRamMB: 1024,
    requiresGpu: false,
    tier: DeviceTier.mid,
    maxTokens: 2048, // Moderate context for mid-tier devices
    contextLimit: 4096,
    sha256: '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be',
    fileType: ModelFileType.litertlm,
    supportedPlatforms: {
      ModelPlatform.linux,
      ModelPlatform.macos,
      ModelPlatform.windows,
    },
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
    maxTokens: 4096, // Larger context for high-end devices
    contextLimit: 4096,
    digestSource: ModelDigestSource.huggingFaceLfs,
    fileType: ModelFileType.task,
    supportedPlatforms: {
      ModelPlatform.web,
      ModelPlatform.android,
      ModelPlatform.ios,
    },
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
    maxTokens: 8192, // Maximum context for premium devices
    contextLimit: 8192,
    digestSource: ModelDigestSource.huggingFaceLfs,
    fileType: ModelFileType.task,
    supportedPlatforms: {
      ModelPlatform.web,
      ModelPlatform.android,
      ModelPlatform.ios,
    },
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
    maxTokens: 256, // Embedding input limit
    // Verified from unauthenticated Hugging Face Git LFS pointer on 2026-07-11.
    sha256: '19f04c9397c814c293d8c6caa045b89da298c77064d65e90d8f85f4c02ad466f',
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
    maxTokens: 256, // Sequence length
    sha256: '37115ef7bff76cd37dd86abe503ff511b1032bf85fc624a85c49c84899e92bc5',
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
    maxTokens: 512, // Sequence length
    sha256: 'ad09e81557203cb0e177abf9bf8727dfe138a7d394aa0f70f0b2ed16432e121a',
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
    maxTokens: 1024, // Sequence length
    sha256: '8b0b8bbd0aa95f9f747c25a6c87cd05a8286933282660f6a50da877662917e31',
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
    required this.maxTokens,
    this.contextLimit,
    this.tokenizerUrl,
    this.sha256,
    this.digestSource = ModelDigestSource.declared,
    this.fileType = ModelFileType.binary,
    this.supportedPlatforms = allPlatforms,
  });

  static const Set<ModelPlatform> allPlatforms = {
    ModelPlatform.web,
    ModelPlatform.android,
    ModelPlatform.ios,
    ModelPlatform.linux,
    ModelPlatform.macos,
    ModelPlatform.windows,
  };

  final String id;
  final String name;
  final String modelUrl;
  final String? tokenizerUrl;
  final AppModelType type;
  final int sizeBytes;
  final int minRamMB;
  final bool requiresGpu;
  final DeviceTier tier;
  final int maxTokens; // Maximum context window (input + output)
  /// Exact context window supported by the model file's KV cache.
  /// [maxTokens] remains the compatibility/default value for older callers.
  final int? contextLimit;
  final String? sha256;
  final ModelDigestSource digestSource;
  final ModelFileType fileType;
  final Set<ModelPlatform> supportedPlatforms;

  /// Whether the registered runtime can load this model on [capabilities].
  bool isCompatibleWith(DeviceCapabilities capabilities) {
    final platform = ModelPlatformParsing.fromDevicePlatform(
      capabilities.platform,
    );
    return platform != null &&
        supportedPlatforms.contains(platform) &&
        (!requiresGpu || capabilities.hasGpu) &&
        minRamMB <= capabilities.totalRamMB &&
        sizeBytes <= capabilities.availableStorageMB * 1024 * 1024;
  }

  /// Get the expected filename from the URL
  String get fileName => modelUrl.split('/').last;

  /// The Hugging Face repo page for [modelUrl].
  String get repoPage => deriveHuggingFaceRepoPage(modelUrl);

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
