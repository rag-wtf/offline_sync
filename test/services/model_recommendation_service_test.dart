import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';

void main() {
  group('ModelRecommendationService', () {
    late ModelRecommendationService service;

    setUp(() {
      service = ModelRecommendationService();
    });

    test('meetsMinimumRequirements checks both RAM and storage', () {
      expect(
        service.meetsMinimumRequirements(
          const DeviceCapabilities(
            totalRamMB: 4096,
            availableStorageMB: 2048,
            hasGpu: false,
            platform: 'android',
          ),
        ),
        isTrue,
      );
      expect(
        service.meetsMinimumRequirements(
          const DeviceCapabilities(
            totalRamMB: 1024,
            availableStorageMB: 2048,
            hasGpu: false,
            platform: 'android',
          ),
        ),
        isFalse,
      );
      expect(
        service.meetsMinimumRequirements(
          const DeviceCapabilities(
            totalRamMB: 4096,
            availableStorageMB: 512,
            hasGpu: false,
            platform: 'android',
          ),
        ),
        isFalse,
      );
    });

    test('unsupported device message lists the missing resources only', () {
      final message = service.getUnsupportedDeviceMessage(
        const DeviceCapabilities(
          totalRamMB: 1024,
          availableStorageMB: 512,
          hasGpu: false,
          platform: 'android',
        ),
      );

      expect(message, contains('RAM: 1024MB'));
      expect(message, contains('Storage: 512MB free'));
    });

    test('selects low-tier models when device does not meet higher tiers', () {
      final recommendation = service.getRecommendedModels(
        const DeviceCapabilities(
          totalRamMB: 3072,
          availableStorageMB: 1536,
          hasGpu: false,
          platform: 'android',
        ),
      );

      expect(recommendation.tier, DeviceTier.low);
      expect(recommendation.inferenceModel, same(InferenceModels.gemma3_270M));
      expect(recommendation.embeddingModel, same(EmbeddingModels.gecko64));
    });

    test('selects mid-tier models at the inclusive threshold', () {
      final recommendation = service.getRecommendedModels(
        const DeviceCapabilities(
          totalRamMB: 4096,
          availableStorageMB: 2048,
          hasGpu: false,
          platform: 'android',
        ),
      );

      expect(recommendation.tier, DeviceTier.mid);
      expect(recommendation.inferenceModel, same(InferenceModels.gemma3_270M));
      expect(
        recommendation.embeddingModel,
        same(EmbeddingModels.embeddingGemma256),
      );
    });

    test('selects high-tier models above the RAM and storage thresholds', () {
      final recommendation = service.getRecommendedModels(
        const DeviceCapabilities(
          totalRamMB: 9000,
          availableStorageMB: 5000,
          hasGpu: false,
          platform: 'linux',
        ),
      );

      expect(recommendation.tier, DeviceTier.high);
      expect(recommendation.inferenceModel, same(InferenceModels.gemma3_1B));
      expect(
        recommendation.embeddingModel,
        same(EmbeddingModels.embeddingGemma512),
      );
    });

    test('selects premium models only when GPU and'
        ' premium thresholds exist', () {
      final recommendation = service.getRecommendedModels(
        const DeviceCapabilities(
          totalRamMB: 13000,
          availableStorageMB: 9000,
          hasGpu: true,
          platform: 'linux',
        ),
      );

      expect(recommendation.tier, DeviceTier.premium);
      expect(recommendation.inferenceModel, same(InferenceModels.gemma3_1B));
      expect(
        recommendation.embeddingModel,
        same(EmbeddingModels.embeddingGemma1024),
      );
    });

    test('filters compatible inference models by size and RAM', () {
      const capabilities = DeviceCapabilities(
        totalRamMB: 4096,
        availableStorageMB: 320,
        hasGpu: false,
        platform: 'android',
      );

      expect(
        service.getCompatibleInferenceModels(capabilities).map((m) => m.id),
        ['gemma3-270m'],
      );
    });

    test('filters compatible embedding models by size and RAM', () {
      const capabilities = DeviceCapabilities(
        totalRamMB: 4096,
        availableStorageMB: 180,
        hasGpu: false,
        platform: 'android',
      );

      expect(
        service.getCompatibleEmbeddingModels(capabilities).map((m) => m.id),
        ['gecko-64', 'embedding-gemma-256', 'embedding-gemma-512'],
      );
    });

    group('platform-compatible recommendations', () {
      final tierCases =
          <
            ({
              DeviceTier tier,
              int ramMB,
              int storageMB,
              bool hasGpu,
              String embeddingId,
            })
          >[
            (
              tier: DeviceTier.low,
              ramMB: 3072,
              storageMB: 1536,
              hasGpu: false,
              embeddingId: 'gecko-64',
            ),
            (
              tier: DeviceTier.mid,
              ramMB: 4096,
              storageMB: 2048,
              hasGpu: false,
              embeddingId: 'embedding-gemma-256',
            ),
            (
              tier: DeviceTier.high,
              ramMB: 9000,
              storageMB: 5000,
              hasGpu: true,
              embeddingId: 'embedding-gemma-512',
            ),
            (
              tier: DeviceTier.premium,
              ramMB: 13000,
              storageMB: 9000,
              hasGpu: true,
              embeddingId: 'embedding-gemma-1024',
            ),
          ];
      final platformCases =
          <
            ({
              String platform,
              ModelFileType fileType,
              List<String> inferenceIds,
            })
          >[
            (
              platform: 'web',
              fileType: ModelFileType.task,
              inferenceIds: [
                'gemma3-270m',
                'gemma3-270m',
                'gemma3n-e2b',
                'gemma3n-e4b',
              ],
            ),
            (
              platform: 'android',
              fileType: ModelFileType.task,
              inferenceIds: [
                'gemma3-270m',
                'gemma3-270m',
                'gemma3n-e2b',
                'gemma3n-e4b',
              ],
            ),
            (
              platform: 'ios',
              fileType: ModelFileType.task,
              inferenceIds: [
                'gemma3-270m',
                'gemma3-270m',
                'gemma3n-e2b',
                'gemma3n-e4b',
              ],
            ),
            (
              platform: 'linux',
              fileType: ModelFileType.litertlm,
              inferenceIds: [
                'gemma3-1b',
                'gemma3-1b',
                'gemma3-1b',
                'gemma3-1b',
              ],
            ),
            (
              platform: 'macos',
              fileType: ModelFileType.litertlm,
              inferenceIds: [
                'gemma3-1b',
                'gemma3-1b',
                'gemma3-1b',
                'gemma3-1b',
              ],
            ),
            (
              platform: 'windows',
              fileType: ModelFileType.litertlm,
              inferenceIds: [
                'gemma3-1b',
                'gemma3-1b',
                'gemma3-1b',
                'gemma3-1b',
              ],
            ),
          ];

      for (final platformCase in platformCases) {
        for (var index = 0; index < tierCases.length; index++) {
          final tierCase = tierCases[index];
          test('${platformCase.platform} ${tierCase.tier.name} tier returns a '
              'runnable pair or the catalog fallback', () {
            final capabilities = DeviceCapabilities(
              totalRamMB: tierCase.ramMB,
              availableStorageMB: tierCase.storageMB,
              hasGpu: tierCase.hasGpu,
              platform: platformCase.platform,
            );

            final recommendation = service.getRecommendedModels(capabilities);

            expect(recommendation.tier, tierCase.tier);
            expect(
              recommendation.inferenceModel.id,
              platformCase.inferenceIds[index],
            );
            expect(recommendation.embeddingModel.id, tierCase.embeddingId);
            expect(
              recommendation.inferenceModel.fileType,
              platformCase.fileType,
            );
            expect(
              recommendation.inferenceModel.isCompatibleWith(capabilities),
              isTrue,
            );
            expect(
              recommendation.embeddingModel.isCompatibleWith(capabilities),
              isTrue,
            );
          });
        }
      }

      test('rejects GPU-only task models when GPU is unavailable', () {
        const capabilities = DeviceCapabilities(
          totalRamMB: 16384,
          availableStorageMB: 16384,
          hasGpu: false,
          platform: 'android',
        );

        expect(
          service
              .getCompatibleInferenceModels(capabilities)
              .map((model) => model.id),
          isNot(contains('gemma3n-e2b')),
        );
        expect(
          service.getRecommendedModels(capabilities).inferenceModel.id,
          'gemma3-270m',
        );
      });
    });
  });
}
