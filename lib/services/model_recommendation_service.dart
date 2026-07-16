import 'dart:developer';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';

/// Recommended models for a device
class RecommendedModels {
  const RecommendedModels({
    required this.inferenceModel,
    required this.embeddingModel,
    required this.tier,
  });

  final ModelDefinition inferenceModel;
  final ModelDefinition embeddingModel;
  final DeviceTier tier;
}

/// Service to recommend models based on device capabilities
class ModelRecommendationService {
  // Minimum requirements (combined inference + embedding)
  static const int minRamMB = 2048; // 2GB minimum
  static const int minStorageMB = 1024; // 1GB minimum

  /// Check if device meets minimum requirements
  bool meetsMinimumRequirements(DeviceCapabilities capabilities) {
    final meetsRam = capabilities.totalRamMB >= minRamMB;
    final meetsStorage = capabilities.availableStorageMB >= minStorageMB;

    log(
      'Requirements check: RAM ${capabilities.totalRamMB}MB >= $minRamMB? '
      '$meetsRam, Storage ${capabilities.availableStorageMB}MB >= '
      '$minStorageMB? $meetsStorage',
    );

    return meetsRam && meetsStorage;
  }

  /// Get user-friendly message for unsupported devices
  String getUnsupportedDeviceMessage(DeviceCapabilities capabilities) {
    final ramIssue = capabilities.totalRamMB < minRamMB;
    final storageIssue = capabilities.availableStorageMB < minStorageMB;

    final buffer = StringBuffer('Your device has limited resources:\n\n');

    if (ramIssue) {
      buffer.write(
        '• RAM: ${capabilities.totalRamMB}MB '
        '(need ${minRamMB}MB minimum)\n',
      );
    }

    if (storageIssue) {
      buffer.write(
        '• Storage: ${capabilities.availableStorageMB}MB free '
        '(need ${minStorageMB}MB minimum)\n',
      );
    }

    return buffer.toString();
  }

  /// Get recommended models based on device capabilities
  RecommendedModels getRecommendedModels(DeviceCapabilities capabilities) {
    final tier = _determineDeviceTier(capabilities);

    log('Device tier: $tier for capabilities: $capabilities');

    switch (tier) {
      case DeviceTier.low:
        return RecommendedModels(
          inferenceModel: InferenceModels.gemma3_270M,
          embeddingModel: EmbeddingModels.gecko64,
          tier: tier,
        );
      case DeviceTier.mid:
        return RecommendedModels(
          inferenceModel: InferenceModels.gemma3_1B,
          embeddingModel: EmbeddingModels.embeddingGemma256,
          tier: tier,
        );
      case DeviceTier.high:
        return RecommendedModels(
          inferenceModel: InferenceModels.gemma3n_2B,
          embeddingModel: EmbeddingModels.embeddingGemma512,
          tier: tier,
        );
      case DeviceTier.premium:
        return RecommendedModels(
          inferenceModel: InferenceModels.gemma3n_4B,
          embeddingModel: EmbeddingModels.embeddingGemma1024,
          tier: tier,
        );
    }
  }

  /// Get list of compatible inference models for this device
  List<ModelDefinition> getCompatibleInferenceModels(
    DeviceCapabilities capabilities,
  ) {
    // Return models that fit within device capabilities
    final allModels = [
      InferenceModels.gemma3_270M,
      InferenceModels.gemma3_1B,
      InferenceModels.gemma3n_2B,
      InferenceModels.gemma3n_4B,
    ];

    return allModels
        .where(
          (model) =>
              model.minRamMB <= capabilities.totalRamMB &&
              model.sizeBytes <= capabilities.availableStorageMB * 1024 * 1024,
        )
        .toList();
  }

  /// Get list of compatible embedding models for this device
  List<ModelDefinition> getCompatibleEmbeddingModels(
    DeviceCapabilities capabilities,
  ) {
    final allModels = [
      EmbeddingModels.gecko64,
      EmbeddingModels.embeddingGemma256,
      EmbeddingModels.embeddingGemma512,
      EmbeddingModels.embeddingGemma1024,
    ];

    return allModels
        .where(
          (model) =>
              model.minRamMB <= capabilities.totalRamMB &&
              model.sizeBytes <= capabilities.availableStorageMB * 1024 * 1024,
        )
        .toList();
  }

  DeviceTier _determineDeviceTier(DeviceCapabilities capabilities) {
    final ramMB = capabilities.totalRamMB;
    final storageMB = capabilities.availableStorageMB;
    final hasGpu = capabilities.hasGpu;

    // Premium: >12GB RAM + GPU + >8GB storage
    if (ramMB > 12288 && hasGpu && storageMB > 8192) {
      return DeviceTier.premium;
    }

    // High: >8GB RAM + >4GB storage
    if (ramMB > 8192 && storageMB > 4096) {
      return DeviceTier.high;
    }

    // Mid: 4-8GB RAM + 2-4GB storage
    if (ramMB >= 4096 && storageMB >= 2048) {
      return DeviceTier.mid;
    }

    // Low: Everything else that meets minimum requirements
    return DeviceTier.low;
  }
}
