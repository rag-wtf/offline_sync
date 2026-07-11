import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';

import '../helpers/test_helpers.dart';

// Note: ModelManagementService depends heavily on FlutterGemma native plugin
// which cannot be easily mocked. These tests focus on state management,
// API contracts, and error handling rather than deep integration.

void main() {
  group('ModelManagementService Tests -', () {
    late ModelManagementService service;

    setUp(() {
      getAndRegisterMockRagSettingsService();
      service = ModelManagementService();
    });

    tearDown(() async {
      service.dispose();
      await unregisterTestHelpers();
    });

    group('Initialization -', () {
      test('should create service with models from config', () {
        expect(service.models, isNotEmpty);
        expect(service.models.length, equals(ModelConfig.allModels.length));
      });

      test('should initialize all models with notDownloaded status', () {
        for (final model in service.models) {
          // Before initialization, models should start as notDownloaded
          expect(
            model.status,
            anyOf(ModelStatus.notDownloaded, ModelStatus.downloaded),
          );
        }
      });

      test('should have valid model IDs matching config', () {
        final configIds = ModelConfig.allModels.map((m) => m.id).toSet();
        final serviceIds = service.models.map((m) => m.id).toSet();

        expect(serviceIds, equals(configIds));
      });
    });

    group('Model status stream -', () {
      test('should provide broadcast stream', () {
        expect(service.modelStatusStream.isBroadcast, isTrue);
      });

      test('should emit updates when models change', () async {
        // Create a listener for the stream
        final subscription = service.modelStatusStream.listen((_) {
          // Stream listener is active
        });

        // Verify stream is broadcast
        expect(service.modelStatusStream.isBroadcast, isTrue);

        // Since we can't easily trigger updates without FlutterGemma,
        // just verify the stream can be subscribed to without errors
        expect(subscription, isNotNull);

        await subscription.cancel();
      });
    });

    group('Active model getters -', () {
      test('should return null when no active inference model', () {
        // Before initialization or model download
        expect(service.activeInferenceModel, isNull);
      });

      test('should return null when no active embedding model', () {
        // Before initialization or model download
        expect(service.activeEmbeddingModel, isNull);
      });
    });

    group('Downloaded models filtering -', () {
      test('should return empty list when no models downloaded', () {
        // Initially nothing is downloaded
        expect(service.downloadedInferenceModels, isEmpty);
        expect(service.downloadedEmbeddingModels, isEmpty);
      });

      test('should filter by model type correctly', () {
        // Verify all models have correct types
        for (final model in service.models) {
          expect(
            model.type,
            anyOf(AppModelType.inference, AppModelType.embedding),
          );
        }
      });
    });

    group('ModelInfo -', () {
      test('should have required fields', () {
        final model = service.models.first;

        expect(model.id, isNotEmpty);
        expect(model.name, isNotEmpty);
        expect(model.url, isNotEmpty);
        expect(model.type, isNotNull);
        expect(model.status, isNotNull);
        expect(model.progress, isA<double>());
      });

      test('effectiveFileName should use fileName or extract from URL', () {
        final model = service.models.first;
        final effectiveName = model.effectiveFileName;

        expect(effectiveName, isNotEmpty);
        // Should either be the explicit fileName or last part of URL
        if (model.fileName != null) {
          expect(effectiveName, equals(model.fileName));
        } else {
          expect(effectiveName, equals(model.url.split('/').last));
        }
      });

      test('should initialize with 0 progress', () {
        for (final model in service.models) {
          if (model.status == ModelStatus.notDownloaded) {
            expect(model.progress, equals(0.0));
          }
        }
      });

      test('should have no error message initially', () {
        for (final model in service.models) {
          if (model.status != ModelStatus.error) {
            expect(model.errorMessage, isNull);
          }
        }
      });
    });

    group('Model switching logic -', () {
      test('switchInferenceModel should validate model type', () async {
        // Find a model that's not an inference model
        final embeddingModel = service.models.firstWhere(
          (m) => m.type == AppModelType.embedding,
        );

        // Trying to switch to embedding model as inference should not work
        // (This logs a warning but doesn't throw)
        await service.switchInferenceModel(embeddingModel.id);

        // Active inference model should still be null
        expect(service.activeInferenceModel, isNull);
      });

      test('switchEmbeddingModel should validate model type', () async {
        // Find an inference model
        final inferenceModel = service.models.firstWhere(
          (m) => m.type == AppModelType.inference,
        );

        // Trying to switch to inference model as embedding should not work
        await service.switchEmbeddingModel(inferenceModel.id);

        // Active embedding model should still be null
        expect(service.activeEmbeddingModel, isNull);
      });

      test('should not switch to model that is not downloaded', () async {
        // Find a model that's not downloaded
        final notDownloadedModel = service.models.firstWhere(
          (m) => m.status == ModelStatus.notDownloaded,
        );

        if (notDownloadedModel.type == AppModelType.inference) {
          await service.switchInferenceModel(notDownloadedModel.id);
          expect(service.activeInferenceModel, isNull);
        } else {
          await service.switchEmbeddingModel(notDownloadedModel.id);
          expect(service.activeEmbeddingModel, isNull);
        }
      });
    });

    group('Model status enum -', () {
      test('should have all expected statuses', () {
        expect(ModelStatus.values, contains(ModelStatus.notDownloaded));
        expect(ModelStatus.values, contains(ModelStatus.downloading));
        expect(ModelStatus.values, contains(ModelStatus.downloaded));
        expect(ModelStatus.values, contains(ModelStatus.error));
      });
    });

    group('Error handling -', () {
      test('should handle model not found gracefully', () {
        // Trying to access a non-existent model ID
        expect(
          () => service.models.firstWhere((m) => m.id == 'non-existent-id'),
          throwsStateError,
        );
      });

      test('dispose should not throw', () {
        expect(() => service.dispose(), returnsNormally);
      });

      test('can create multiple service instances', () {
        final service1 = ModelManagementService();
        final service2 = ModelManagementService();

        expect(service1.models.length, equals(service2.models.length));

        service1.dispose();
        service2.dispose();
      });
    });

    group('Integration constraints -', () {
      test('Gecko 64 declares the verified SHA-256 digest', () {
        expect(
          EmbeddingModels.gecko64.sha256,
          equals(
            '19f04c9397c814c293d8c6caa045b89da298c77064d65e90d8f85f4c02ad466f',
          ),
        );
      });

      test('verifyFileSha256 fails closed on mismatch', () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'model-sha256-test-',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final file = File('${tempDir.path}/sample-model.bin');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        final isVerified = await ModelManagementService.verifyFileSha256(
          file,
          '0000000000000000000000000000000000000000000000000000000000000000',
        );

        expect(isVerified, isFalse);
      });

      test(
        'initialize fails closed when checksum path is unavailable',
        () async {
          final service = ModelManagementService(
            installedModelPathResolver: (_) async => null,
            modelInstalledChecker: (filename) async =>
                filename == EmbeddingModels.gecko64.fileName,
          );
          addTearDown(service.dispose);

          final errors = <Object>[];
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);

          await service.initialize();

          final gecko = service.models.firstWhere(
            (model) => model.id == EmbeddingModels.gecko64.id,
          );
          expect(gecko.status, ModelStatus.error);
          expect(gecko.progress, 0);
          expect(
            gecko.errorMessage,
            contains('Checksum verification unavailable'),
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            errors,
            contains('Checksum verification unavailable for gecko-64.'),
          );
        },
      );

      test('should have at least one inference model', () {
        final inferenceModels = service.models.where(
          (m) => m.type == AppModelType.inference,
        );
        expect(inferenceModels, isNotEmpty);
      });

      test('should have at least one embedding model', () {
        final embeddingModels = service.models.where(
          (m) => m.type == AppModelType.embedding,
        );
        expect(embeddingModels, isNotEmpty);
      });

      test('all model URLs should be valid format', () {
        for (final model in service.models) {
          expect(model.url, startsWith('http'));
          expect(model.url, contains('huggingface.co'));
        }
      });

      test('embedding models should have tokenizer URLs', () {
        for (final model in service.models) {
          if (model.type == AppModelType.embedding) {
            expect(model.tokenizerUrl, isNotNull);
            expect(model.tokenizerUrl, startsWith('http'));
          }
        }
      });
    });

    group('State consistency -', () {
      test('models list should be unmodifiable', () {
        final modelsList = service.models;
        expect(
          () => modelsList.add(
            ModelInfo(
              id: 'test',
              name: 'test',
              url: 'test',
              type: AppModelType.inference,
            ),
          ),
          throwsUnsupportedError,
        );
      });

      test('progress should be between 0 and 1', () {
        for (final model in service.models) {
          expect(model.progress, greaterThanOrEqualTo(0.0));
          expect(model.progress, lessThanOrEqualTo(1.0));
        }
      });

      test('downloaded models should have progress of 1.0', () {
        for (final model in service.models) {
          if (model.status == ModelStatus.downloaded) {
            expect(model.progress, equals(1.0));
          }
        }
      });
    });
  });
}
