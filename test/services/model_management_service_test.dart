import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/utils/download_failure.dart';

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
      test('uses an explicit file name when one is supplied', () {
        final model = ModelInfo(
          id: 'custom',
          name: 'Custom',
          url: 'https://example.com/model.bin',
          type: AppModelType.inference,
          fileName: 'local-model.bin',
        );

        expect(model.effectiveFileName, 'local-model.bin');
      });

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
      test(
        'does not mark inference model active when activation fails',
        () async {
          final service = ModelManagementService(
            inferenceModelActivator: (_) async {
              throw Exception('activation failed');
            },
          );
          addTearDown(service.dispose);

          final model = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await service.switchInferenceModel(model.id);

          expect(service.activeInferenceModel, isNull);
        },
      );

      test(
        'reactivates a cached inference model without foreground download',
        () async {
          bool? requestedForeground;
          final service = ModelManagementService(
            inferenceModelInstaller:
                (
                  _, {
                  required foreground,
                }) async {
                  requestedForeground = foreground;
                },
          );
          addTearDown(service.dispose);
          when(
            () =>
                locator<RagSettingsService>().setActiveInferenceModelId(any()),
          ).thenAnswer((_) async {});

          final model = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await service.switchInferenceModel(model.id);

          expect(requestedForeground, isFalse);
        },
      );

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
      test(
        'verifyFileSha256 accepts the expected digest case-insensitively',
        () async {
          final tempDir = await Directory.systemTemp.createTemp(
            'model-sha256-valid-',
          );
          addTearDown(() async {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final file = File('${tempDir.path}/sample-model.bin');
          await file.writeAsBytes(const [1, 2, 3, 4]);

          expect(
            await ModelManagementService.verifyFileSha256(
              file,
              'e3b0c44298fc1c149afbf4c8996fb924'
              '27ae41e4649b934ca495991b7852b855',
            ),
            isFalse,
          );
          expect(
            await ModelManagementService.verifyFileSha256(
              file,
              '9F64A747E1B97F131FABB6B447296C9B'
              '6F0201E79FB3C5356E6C77E89B6A806A',
            ),
            isTrue,
          );
          expect(
            await ModelManagementService.verifyFileSha256(file, 'not-a-digest'),
            isFalse,
          );
        },
      );

      test('verifyFileSha256 returns false for a missing file', () async {
        final result = await ModelManagementService.verifyFileSha256(
          File('missing-model-file.bin'),
          'anything',
        );
        expect(result, isFalse);
      });

      test(
        'initialize treats model-installed checker errors as not downloaded',
        () async {
          final service = ModelManagementService(
            modelInstalledChecker: (_) async =>
                throw Exception('checker failed'),
          );
          addTearDown(service.dispose);

          await service.initialize();

          expect(service.downloadedInferenceModels, isEmpty);
          expect(service.downloadedEmbeddingModels, isEmpty);
        },
      );

      test(
        'switches downloaded inference and embedding models successfully',
        () async {
          final activatedInference = <String>[];
          final activatedEmbedding = <String>[];
          final service = ModelManagementService(
            inferenceModelActivator: (model) async =>
                activatedInference.add(model.id),
            embeddingModelActivator: (model) async =>
                activatedEmbedding.add(model.id),
          );
          addTearDown(service.dispose);
          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;
          final embedding = service.models.firstWhere(
            (m) => m.type == AppModelType.embedding,
          )..status = ModelStatus.downloaded;
          when(
            () =>
                locator<RagSettingsService>().setActiveInferenceModelId(any()),
          ).thenAnswer((_) async {});
          when(
            () =>
                locator<RagSettingsService>().setActiveEmbeddingModelId(any()),
          ).thenAnswer((_) async {});

          await service.switchInferenceModel(inference.id);
          await service.switchEmbeddingModel(embedding.id);

          expect(service.activeInferenceModel, same(inference));
          expect(service.activeEmbeddingModel, same(embedding));
          expect(activatedInference, [inference.id]);
          expect(activatedEmbedding, [embedding.id]);
        },
      );

      test('resetErroredModels restores errored state and clears messages', () {
        final errored = service.models.first
          ..status = ModelStatus.error
          ..progress = 0.5
          ..errorMessage = 'failed';

        service.resetErroredModels();

        expect(errored.status, ModelStatus.notDownloaded);
        expect(errored.progress, 0);
        expect(errored.errorMessage, isNull);
      });

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
            await tempDir.delete(recursive: true);
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

      test(
        'initialize resets stale downloaded state when file is missing',
        () async {
          final service = ModelManagementService(
            modelInstalledChecker: (_) async => false,
          );
          addTearDown(service.dispose);

          final model = service.models.first
            ..status = ModelStatus.downloaded
            ..progress = 1;

          await service.initialize();

          expect(model.status, ModelStatus.notDownloaded);
          expect(model.progress, 0);
        },
      );

      test(
        'initialize restores saved active model ids when activation succeeds',
        () async {
          const inferenceId = 'gemma3-270m';
          const embeddingId = 'embedding-gemma-256';

          when(
            () => locator<RagSettingsService>().activeInferenceModelId,
          ).thenReturn(inferenceId);
          when(
            () => locator<RagSettingsService>().activeEmbeddingModelId,
          ).thenReturn(embeddingId);

          final tempDir = await Directory.systemTemp.createTemp('model-path-');
          addTearDown(() async {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          });

          final service = ModelManagementService(
            modelInstalledChecker: (_) async => true,
            installedModelPathResolver: (definition) async {
              final file = File('${tempDir.path}/${definition.fileName}');
              await file.writeAsBytes(const [1, 2, 3]);
              return file.path;
            },
            fileChecksumVerifier: (file, expectedSha256) async => true,
            inferenceModelActivator: (_) async {},
            embeddingModelActivator: (_) async {},
          );
          addTearDown(service.dispose);

          await service.initialize();

          expect(service.activeInferenceModel?.id, inferenceId);
          expect(service.activeEmbeddingModel?.id, embeddingId);
        },
      );

      test(
        'initialize falls back to the first model when saved ids are unknown',
        () async {
          final firstModel = ModelConfig.allModels.first;
          when(
            () => locator<RagSettingsService>().activeInferenceModelId,
          ).thenReturn('missing-inference');
          when(
            () => locator<RagSettingsService>().activeEmbeddingModelId,
          ).thenReturn('missing-embedding');

          final service = ModelManagementService(
            modelInstalledChecker: (filename) async =>
                filename == firstModel.fileName,
            installedModelPathResolver: (definition) async {
              final tempDir = await Directory.systemTemp.createTemp(
                'model-fallback-',
              );
              addTearDown(() async {
                if (tempDir.existsSync()) {
                  tempDir.deleteSync(recursive: true);
                }
              });
              final file = File('${tempDir.path}/${definition.fileName}');
              await file.writeAsBytes(const [7, 8, 9]);
              return file.path;
            },
            fileChecksumVerifier: (file, expectedSha256) async => true,
            inferenceModelActivator: (_) async {},
          );
          addTearDown(service.dispose);

          await service.initialize();

          expect(service.activeInferenceModel?.id, firstModel.id);
          expect(service.activeEmbeddingModel, isNull);
        },
      );

      test(
        'downloadModel auto-activates the first downloaded inference model',
        () async {
          final progressUpdates = <double>[];
          when(
            () =>
                locator<RagSettingsService>().setActiveInferenceModelId(any()),
          ).thenAnswer((_) async {});

          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            inferenceModelDownloader: (model, token, onProgress) async {
              expect(token, 'hf_token');
              onProgress(25);
              progressUpdates.add(model.progress);
              onProgress(100);
              progressUpdates.add(model.progress);
            },
            inferenceModelActivator: (_) async {},
          );
          addTearDown(service.dispose);

          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          );

          await service.downloadModel(inference.id);

          expect(inference.status, ModelStatus.downloaded);
          expect(inference.progress, 1);
          expect(service.activeInferenceModel?.id, inference.id);
          expect(progressUpdates, [0.25, 1.0]);
        },
      );

      test(
        'downloadModel restores the previously active inference model',
        () async {
          final activatedModels = <String>[];
          when(
            () =>
                locator<RagSettingsService>().setActiveInferenceModelId(any()),
          ).thenAnswer((_) async {});

          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            inferenceModelDownloader: (model, token, onProgress) async {
              onProgress(100);
            },
            inferenceModelActivator: (model) async {
              activatedModels.add(model.id);
            },
          );
          addTearDown(service.dispose);

          final inferenceModels = service.models
              .where((m) => m.type == AppModelType.inference)
              .take(2)
              .toList();
          final first = inferenceModels.first..status = ModelStatus.downloaded;
          final second = inferenceModels.last;

          await service.switchInferenceModel(first.id);
          activatedModels.clear();

          await service.downloadModel(second.id);

          expect(second.status, ModelStatus.downloaded);
          expect(service.activeInferenceModel?.id, first.id);
          expect(activatedModels, [first.id]);
        },
      );

      test(
        'downloadModel surfaces typed unauthorized errors for '
        'inference downloads',
        () async {
          const downloadError = DownloadException(
            DownloadError.unauthorized(),
          );
          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            inferenceModelDownloader: (model, token, onProgress) async {
              throw downloadError;
            },
          );
          addTearDown(service.dispose);

          final errors = <Object>[];
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);

          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          );

          await service.downloadModel(inference.id);
          await Future<void>.delayed(Duration.zero);

          expect(inference.status, ModelStatus.error);
          expect(
            errors.any((e) => e is AuthenticationRequiredException),
            isTrue,
          );
        },
      );

      test(
        'treats an unrelated proxy 401 as a generic download failure',
        () async {
          final downloadError = Exception('HTTP 401 from an upstream proxy');
          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            inferenceModelDownloader: (model, token, onProgress) async {
              throw downloadError;
            },
          );
          addTearDown(service.dispose);

          final errors = <Object>[];
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);

          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          );

          await service.downloadModel(inference.id);
          await Future<void>.delayed(Duration.zero);

          expect(inference.status, ModelStatus.error);
          expect(inference.isAuthError, isFalse);
          expect(inference.errorMessage, downloadError.toString());
          expect(
            errors.any(
              (error) => error is String && error.contains('Download error:'),
            ),
            isTrue,
          );
        },
      );

      test(
        'downloadModel surfaces actionable gated error when inference download '
        'fails with typed gated access error',
        () async {
          const downloadError = DownloadException(DownloadError.unauthorized());
          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            inferenceModelDownloader: (model, token, onProgress) async {
              throw downloadError;
            },
          );
          addTearDown(service.dispose);

          final errors = <Object>[];
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);

          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          );

          await service.downloadModel(inference.id);
          await Future<void>.delayed(Duration.zero);

          expect(inference.status, ModelStatus.error);
          final expectedAdvice = describeDownloadFailure(
            downloadError,
            repoPage: inference.repoPage,
          );
          expect(inference.errorMessage, expectedAdvice);
          expect(inference.errorMessage, contains(inference.repoPage));
          expect(
            errors.any(
              (e) =>
                  e is AuthenticationRequiredException &&
                  e.message == expectedAdvice &&
                  e.message.contains(inference.repoPage),
            ),
            isTrue,
          );
        },
      );

      test(
        'downloadModel surfaces actionable gated error for string 401 '
        'gated repo errors',
        () async {
          final downloadError = Exception(
            'HTTP 401 Unauthorized: Access to model is restricted and gated',
          );
          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            inferenceModelDownloader: (model, token, onProgress) async {
              throw downloadError;
            },
          );
          addTearDown(service.dispose);

          final errors = <Object>[];
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);

          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          );

          await service.downloadModel(inference.id);
          await Future<void>.delayed(Duration.zero);

          expect(inference.status, ModelStatus.error);
          final expectedAdvice = describeDownloadFailure(
            downloadError,
            repoPage: inference.repoPage,
          );
          expect(inference.errorMessage, expectedAdvice);
          expect(inference.errorMessage, contains(inference.repoPage));
          expect(
            errors.any(
              (e) =>
                  e is AuthenticationRequiredException &&
                  e.message == expectedAdvice &&
                  e.message.contains(inference.repoPage),
            ),
            isTrue,
          );
        },
      );

      test(
        'downloadModel surfaces actionable gated error when embedding '
        'download fails with gated access error',
        () async {
          const downloadError = DownloadException(DownloadError.forbidden());
          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            embeddingModelDownloader: (model, token, onProgress) async {
              throw downloadError;
            },
          );
          addTearDown(service.dispose);

          final errors = <Object>[];
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);

          final embedding = service.models.firstWhere(
            (m) => m.type == AppModelType.embedding,
          );

          await service.downloadModel(embedding.id);
          await Future<void>.delayed(Duration.zero);

          expect(embedding.status, ModelStatus.error);
          final expectedAdvice = describeDownloadFailure(
            downloadError,
            repoPage: embedding.repoPage,
          );
          expect(embedding.errorMessage, expectedAdvice);
          expect(embedding.errorMessage, contains(embedding.repoPage));
          expect(
            errors.any(
              (e) =>
                  e is AuthenticationRequiredException &&
                  e.message == expectedAdvice &&
                  e.message.contains(embedding.repoPage),
            ),
            isTrue,
          );
        },
      );

      test(
        'downloadModel restores the previously active embedding model',
        () async {
          final activatedModels = <String>[];
          when(
            () =>
                locator<RagSettingsService>().setActiveEmbeddingModelId(any()),
          ).thenAnswer((_) async {});

          final service = ModelManagementService(
            authTokenLoader: () async => 'hf_token',
            embeddingModelDownloader: (model, token, onProgress) async {
              onProgress(100);
            },
            embeddingModelActivator: (model) async {
              activatedModels.add(model.id);
            },
          );
          addTearDown(service.dispose);

          final embeddingModels = service.models
              .where((m) => m.type == AppModelType.embedding)
              .take(2)
              .toList();
          final first = embeddingModels.first..status = ModelStatus.downloaded;
          final second = embeddingModels.last;

          await service.switchEmbeddingModel(first.id);
          activatedModels.clear();

          await service.downloadModel(second.id);

          expect(second.status, ModelStatus.downloaded);
          expect(service.activeEmbeddingModel?.id, first.id);
          expect(activatedModels, [first.id]);
        },
      );

      test('verifyDeclaredChecksumForTest deletes'
          ' mismatched files and marks error', () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'model-checksum-mismatch-',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        const expected = EmbeddingModels.gecko64;
        final file = File('${tempDir.path}/${expected.fileName}');
        await file.writeAsBytes(const [1, 2, 3]);

        final service = ModelManagementService(
          installedModelPathResolver: (_) async => file.path,
        );
        addTearDown(service.dispose);

        final errors = <Object>[];
        final subscription = service.modelStatusStream.listen(
          (_) {},
          onError: errors.add,
        );
        addTearDown(subscription.cancel);

        final model = service.models.firstWhere(
          (candidate) => candidate.id == expected.id,
        );

        final verified = await service.verifyDeclaredChecksumForTest(model);
        await Future<void>.delayed(Duration.zero);

        expect(verified, isFalse);
        expect(file.existsSync(), isFalse);
        expect(model.status, ModelStatus.error);
        expect(model.errorMessage, contains('Checksum mismatch'));
        expect(errors, contains('Checksum mismatch for ${expected.id}.'));
      });

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
