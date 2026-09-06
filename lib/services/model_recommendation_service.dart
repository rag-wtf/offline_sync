import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/model_config.dart';

void log(String message, {String? name}) =>
    LoggingService.debug(LoggingService.redact(message), name: name);

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

enum UnsupportedDeviceResource { ram, storage }

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
  String getUnsupportedDeviceMessage(
    DeviceCapabilities capabilities, {
    required String intro,
    required String Function(int actual, int minimum) ramMessage,
    required String Function(int actual, int minimum) storageMessage,
  }) {
    final ramIssue = capabilities.totalRamMB < minRamMB;
    final storageIssue = capabilities.availableStorageMB < minStorageMB;

    final buffer = StringBuffer(intro);

    if (ramIssue) {
      buffer.write('\n\n${ramMessage(capabilities.totalRamMB, minRamMB)}');
    }

    if (storageIssue) {
      buffer.write(
        '\n\n${storageMessage(capabilities.availableStorageMB, minStorageMB)}',
      );
    }

    return buffer.toString();
  }

  /// Get recommended models based on device capabilities
  RecommendedModels getRecommendedModels(DeviceCapabilities capabilities) {
    final tier = _determineDeviceTier(capabilities);

    log('Device tier: $tier for capabilities: $capabilities');

    return RecommendedModels(
      inferenceModel: _selectForTier(
        getCompatibleInferenceModels(capabilities),
        tier,
        AppModelType.inference,
      ),
      embeddingModel: _selectForTier(
        getCompatibleEmbeddingModels(capabilities),
        tier,
        AppModelType.embedding,
      ),
      tier: tier,
    );
  }

  /// Get list of compatible inference models for this device
  List<ModelDefinition> getCompatibleInferenceModels(
    DeviceCapabilities capabilities,
  ) {
    return InferenceModels.all
        .where((model) => model.isCompatibleWith(capabilities))
        .toList();
  }

  /// Get list of compatible embedding models for this device
  List<ModelDefinition> getCompatibleEmbeddingModels(
    DeviceCapabilities capabilities,
  ) {
    return EmbeddingModels.all
        .where((model) => model.isCompatibleWith(capabilities))
        .toList();
  }

  /// A lower compatible pair offered before a first-run download. Returns null
  /// when the current pair is already the smallest runnable choice.
  RecommendedModels? getSmallerCompatibleModels(
    DeviceCapabilities capabilities,
    RecommendedModels current,
  ) {
    final currentRank = DeviceTier.values.indexOf(current.tier);
    if (currentRank == 0) return null;
    final lowerTiers = DeviceTier.values.take(currentRank).toList().reversed;
    for (final tier in lowerTiers) {
      final inference =
          getCompatibleInferenceModels(
            capabilities,
          ).where((model) => model.tier == tier).firstOrNull ??
          getCompatibleInferenceModels(capabilities).firstOrNull;
      final embedding =
          getCompatibleEmbeddingModels(
            capabilities,
          ).where((model) => model.tier == tier).firstOrNull ??
          getCompatibleEmbeddingModels(capabilities).firstOrNull;
      if (inference != null && embedding != null) {
        if (inference.id != current.inferenceModel.id ||
            embedding.id != current.embeddingModel.id) {
          return RecommendedModels(
            inferenceModel: inference,
            embeddingModel: embedding,
            tier: tier,
          );
        }
      }
    }
    return null;
  }

  ModelDefinition _selectForTier(
    List<ModelDefinition> compatible,
    DeviceTier desiredTier,
    AppModelType type,
  ) {
    if (compatible.isEmpty) {
      throw StateError('No compatible ${type.name} model is registered.');
    }
    return compatible.firstWhere(
      (model) => model.tier == desiredTier,
      orElse: () => compatible.first,
    );
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
