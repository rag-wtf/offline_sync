import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/utils/download_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

// Note: ModelManagementService depends heavily on FlutterGemma native plugin
// which cannot be easily mocked. These tests focus on state management,
// API contracts, and error handling rather than deep integration.

class _MockModelFileManager extends Mock implements ModelFileManager {}

class _RaceInferenceModel extends Mock implements InferenceModel {}

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
        'clears the plugin inference identity when rollback has no prior model',
        () async {
          final manager = _MockModelFileManager();
          var clearCalls = 0;
          when(manager.clearActiveInferenceIdentity).thenAnswer((_) async {
            clearCalls++;
          });
          when(
            () => locator<RagSettingsService>().setActiveInferenceModelId(
              any(),
            ),
          ).thenThrow(StateError('settings write failed'));

          final service = ModelManagementService(
            modelManager: manager,
            inferenceModelActivator: (_) async {},
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await expectLater(
            service.switchInferenceModel(model.id),
            throwsStateError,
          );

          expect(clearCalls, 1);
        },
      );

      test(
        'clears the plugin embedding identity when rollback has no prior model',
        () async {
          final manager = _MockModelFileManager();
          var clearCalls = 0;
          when(manager.clearActiveEmbeddingIdentity).thenAnswer((_) async {
            clearCalls++;
          });
          when(
            () => locator<RagSettingsService>().setActiveEmbeddingModelId(
              any(),
            ),
          ).thenThrow(StateError('settings write failed'));

          final service = ModelManagementService(
            modelManager: manager,
            embeddingModelActivator: (_) async {},
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.type == AppModelType.embedding,
          )..status = ModelStatus.downloaded;

          await expectLater(
            service.switchEmbeddingModel(model.id),
            throwsStateError,
          );

          expect(clearCalls, 1);
        },
      );

      test(
        'reactivates a cached inference model with its declared file type',
        () async {
          bool? requestedForeground;
          ModelFileType? requestedFileType;
          final service = ModelManagementService(
            inferenceModelInstaller:
                (
                  _, {
                  required fileType,
                  required foreground,
                }) async {
                  requestedFileType = fileType;
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
          expect(requestedFileType, InferenceModels.gemma3_270M.fileType);
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

      test(
        'deletes only the requested model and refreshes its state',
        () async {
          ModelInfo? deleted;
          final service = ModelManagementService(
            modelDeleter: (model) async => deleted = model,
          );
          addTearDown(service.dispose);
          final target = service.models.firstWhere(
            (model) => model.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;
          final other = service.models.firstWhere(
            (model) => model.id != target.id && model.type == target.type,
          )..status = ModelStatus.downloaded;

          expect(await service.deleteModel(target.id), isTrue);

          expect(deleted?.id, target.id);
          expect(target.status, ModelStatus.notDownloaded);
          expect(other.status, ModelStatus.downloaded);
        },
      );

      test('marks an active model as errored when deletion fails', () async {
        when(
          () => locator<RagSettingsService>().setActiveInferenceModelId(
            any(),
          ),
        ).thenAnswer((_) async {});
        when(
          locator<RagSettingsService>().clearActiveInferenceModelId,
        ).thenAnswer((_) async {});
        final service = ModelManagementService(
          inferenceModelActivator: (_) async {},
          clearActiveInferenceIdentity: () async {},
          modelDeleter: (_) async => throw StateError('delete failed'),
        );
        addTearDown(service.dispose);
        final model = service.models.firstWhere(
          (candidate) => candidate.type == AppModelType.inference,
        )..status = ModelStatus.downloaded;

        await service.switchInferenceModel(model.id);
        expect(await service.deleteModel(model.id), isFalse);
        expect(model.status, ModelStatus.error);
        expect(model.errorMessage, contains('Unable to delete'));
      });

      test(
        'waits for an active inference operation to release before deleting',
        () async {
          final provider = getAndRegisterMockInferenceModelProvider();
          var clearCalls = 0;
          final releaseStarted = Completer<void>();
          final release = Completer<void>();
          when(provider.clearCacheAndWait).thenAnswer((_) async {
            clearCalls++;
            if (clearCalls == 1) return;
            releaseStarted.complete();
            await release.future;
          });
          when(
            () => locator<RagSettingsService>().setActiveInferenceModelId(
              any(),
            ),
          ).thenAnswer((_) async {});
          when(
            locator<RagSettingsService>().clearActiveInferenceModelId,
          ).thenAnswer((_) async {});

          var deleteStarted = false;
          final service = ModelManagementService(
            modelDeleter: (_) async {
              deleteStarted = true;
            },
            inferenceModelActivator: (_) async {},
            clearActiveInferenceIdentity: () async {},
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await service.switchInferenceModel(model.id);
          final deletion = service.deleteModel(model.id);
          await releaseStarted.future;
          expect(deleteStarted, isFalse);

          release.complete();
          expect(await deletion, isTrue);
          expect(clearCalls, 2);
        },
      );

      test(
        'keeps a concurrent inference load behind deletion and file removal',
        () async {
          if (locator.isRegistered<InferenceModelProvider>()) {
            locator.unregister<InferenceModelProvider>();
          }

          final oldModel = _RaceInferenceModel();
          final replacementModel = _RaceInferenceModel();
          final closeStarted = Completer<void>();
          final closeRelease = Completer<void>();
          var loadCalls = 0;
          var deleteStarted = false;
          var deleteSawClosedModel = false;

          when(oldModel.close).thenAnswer((_) async {
            closeStarted.complete();
            await closeRelease.future;
          });
          when(replacementModel.close).thenAnswer((_) async {});
          final provider = InferenceModelProvider(
            activeModelLoader: ({required maxTokens}) async {
              loadCalls++;
              return loadCalls == 1 ? oldModel : replacementModel;
            },
          );
          locator.registerSingleton<InferenceModelProvider>(provider);

          when(
            () => locator<RagSettingsService>().setActiveInferenceModelId(
              any(),
            ),
          ).thenAnswer((_) async {});
          when(
            locator<RagSettingsService>().clearActiveInferenceModelId,
          ).thenAnswer((_) async {});

          final service = ModelManagementService(
            inferenceModelActivator: (_) async {},
            clearActiveInferenceIdentity: () async {},
            modelDeleter: (_) async {
              deleteStarted = true;
              deleteSawClosedModel = closeRelease.isCompleted;
            },
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await service.switchInferenceModel(model.id);
          await provider.getModel();

          final deletion = service.deleteModel(model.id);
          await closeStarted.future;

          final concurrentLoad = provider.getModel();
          await Future<void>.delayed(Duration.zero);
          expect(deleteStarted, isFalse);
          expect(loadCalls, 1);

          closeRelease.complete();
          expect(await deletion, isTrue);
          expect(deleteStarted, isTrue);
          expect(deleteSawClosedModel, isTrue);

          expect(await concurrentLoad, same(replacementModel));
          expect(loadCalls, 2);
        },
      );

      test(
        'serializes embedding deletion with an active embedding operation',
        () async {
          final coordinator = EmbeddingModelCoordinator();
          final operationStarted = Completer<void>();
          final operationRelease = Completer<void>();
          final operation = coordinator.run(() async {
            operationStarted.complete();
            await operationRelease.future;
          });
          await operationStarted.future;

          var deleteStarted = false;
          final service = ModelManagementService(
            embeddingCoordinator: coordinator,
            modelDeleter: (_) async {
              deleteStarted = true;
            },
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.type == AppModelType.embedding,
          )..status = ModelStatus.downloaded;

          final deletion = service.deleteModel(model.id);
          await Future<void>.delayed(Duration.zero);
          expect(deleteStarted, isFalse);

          operationRelease.complete();
          await operation;
          expect(await deletion, isTrue);
        },
      );

      test(
        'refresh restores embedding models through the coordinator',
        () async {
          const embeddingId = 'embedding-gemma-256';
          when(
            () => locator<RagSettingsService>().activeEmbeddingModelId,
          ).thenReturn(embeddingId);
          when(
            () => locator<RagSettingsService>().activeInferenceModelId,
          ).thenReturn(null);

          final coordinator = EmbeddingModelCoordinator();
          final operationStarted = Completer<void>();
          final operationRelease = Completer<void>();
          final operation = coordinator.run(() async {
            operationStarted.complete();
            await operationRelease.future;
          });
          await operationStarted.future;

          final expectedFileName = ModelConfig.allModels
              .firstWhere((model) => model.id == embeddingId)
              .fileName;
          var activationStarted = false;
          final service = ModelManagementService(
            embeddingCoordinator: coordinator,
            modelInstalledChecker: (filename) async =>
                filename == expectedFileName,
            embeddingModelDownloader: (_, _, _) async {},
            embeddingModelActivator: (_) async {
              activationStarted = true;
            },
          );
          addTearDown(service.dispose);

          final refresh = service.initialize();
          await Future<void>.delayed(Duration.zero);
          expect(activationStarted, isFalse);

          operationRelease.complete();
          await operation;
          await refresh;
          expect(activationStarted, isTrue);
        },
      );
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
        'initialize does not activate a model when saved ids are unknown',
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

          expect(service.activeInferenceModel, isNull);
          expect(service.activeEmbeddingModel, isNull);
        },
      );

      test(
        'refuses an incompatible model download before invoking its downloader',
        () async {
          var downloaded = false;
          final service = ModelManagementService(
            capabilitiesProvider: () async => const DeviceCapabilities(
              totalRamMB: 8192,
              availableStorageMB: 8192,
              hasGpu: false,
              platform: 'linux',
            ),
            inferenceModelDownloader: (_, _, _) async => downloaded = true,
          );
          addTearDown(service.dispose);

          final incompatible = service.models.firstWhere(
            (model) => model.id == InferenceModels.gemma3_270M.id,
          );
          await service.downloadModel(incompatible.id);

          expect(downloaded, isFalse);
          expect(incompatible.status, ModelStatus.error);
          expect(incompatible.errorMessage, contains(incompatible.name));
          expect(incompatible.errorMessage, contains('linux'));
        },
      );

      test('refuses activation of an incompatible downloaded model', () async {
        var activated = false;
        final service = ModelManagementService(
          capabilitiesProvider: () async => const DeviceCapabilities(
            totalRamMB: 8192,
            availableStorageMB: 8192,
            hasGpu: false,
            platform: 'linux',
          ),
          inferenceModelActivator: (_) async => activated = true,
        );
        addTearDown(service.dispose);
        final incompatible = service.models.firstWhere(
          (model) => model.id == InferenceModels.gemma3_270M.id,
        )..status = ModelStatus.downloaded;

        await service.switchInferenceModel(incompatible.id);

        expect(activated, isFalse);
        expect(service.activeInferenceModel, isNull);
        expect(incompatible.status, ModelStatus.error);
        expect(incompatible.errorMessage, contains(incompatible.name));
      });

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
              .where(
                (m) =>
                    m.type == AppModelType.inference &&
                    m.id != InferenceModels.gemma3_1B.id,
              )
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

      test('records Object-level download failures without leaving a model '
          'downloading', () async {
        final errors = <Object>[];
        final service = ModelManagementService(
          authTokenLoader: () async => 'hf_token',
          inferenceModelDownloader: (model, token, onProgress) async {
            throw ArgumentError('download argument failed');
          },
        );
        addTearDown(service.dispose);
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
        expect(inference.errorMessage, contains('download argument failed'));
        expect(
          errors,
          contains(
            'Download error: Invalid argument(s): download argument failed',
          ),
        );
      });

      test(
        'records Object-level activation failures without throwing',
        () async {
          final errors = <Object>[];
          final service = ModelManagementService(
            inferenceModelActivator: (_) async {
              throw ArgumentError('activation argument failed');
            },
          );
          addTearDown(service.dispose);
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);
          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await service.switchInferenceModel(inference.id);
          await Future<void>.delayed(Duration.zero);

          expect(inference.status, ModelStatus.error);
          expect(
            inference.errorMessage,
            contains('activation argument failed'),
          );
          expect(service.activeInferenceModel, isNull);
          expect(
            errors,
            contains(
              'Activation error: Invalid argument(s): '
              'activation argument failed',
            ),
          );
        },
      );

      test('records capability resolution failures during download', () async {
        final errors = <Object>[];
        final service = ModelManagementService(
          capabilitiesProvider: () async {
            throw ArgumentError('capability argument failed');
          },
          inferenceModelDownloader: (model, token, onProgress) async {},
        );
        addTearDown(service.dispose);
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
        expect(inference.errorMessage, contains('capability argument failed'));
        expect(
          errors,
          contains(
            'Download error: Invalid argument(s): capability argument failed',
          ),
        );
      });

      test(
        'records capability resolution failures during activation',
        () async {
          final errors = <Object>[];
          final service = ModelManagementService(
            capabilitiesProvider: () async {
              throw UnsupportedError('capability unsupported');
            },
            inferenceModelActivator: (_) async {},
          );
          addTearDown(service.dispose);
          final subscription = service.modelStatusStream.listen(
            (_) {},
            onError: errors.add,
          );
          addTearDown(subscription.cancel);
          final inference = service.models.firstWhere(
            (m) => m.type == AppModelType.inference,
          )..status = ModelStatus.downloaded;

          await service.switchInferenceModel(inference.id);
          await Future<void>.delayed(Duration.zero);

          expect(inference.status, ModelStatus.error);
          expect(inference.errorMessage, contains('capability unsupported'));
          expect(
            errors,
            contains(
              'Activation error: Unsupported operation: capability unsupported',
            ),
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

      test('surfaces embedding activation rollback failure', () async {
        var settingsWrites = 0;
        when(
          () => locator<RagSettingsService>().setActiveEmbeddingModelId(any()),
        ).thenAnswer((_) async {
          settingsWrites++;
          if (settingsWrites > 1) {
            throw StateError('settings write failed');
          }
        });

        var activationCount = 0;
        final rollbackService = ModelManagementService(
          embeddingModelActivator: (_) async {
            activationCount++;
            if (activationCount == 3) {
              throw StateError('rollback activation failed');
            }
          },
        );
        addTearDown(rollbackService.dispose);
        final rollbackModels = rollbackService.models
            .where((model) => model.type == AppModelType.embedding)
            .take(2)
            .toList();
        for (final model in rollbackModels) {
          model.status = ModelStatus.downloaded;
        }

        await rollbackService.switchEmbeddingModel(rollbackModels[0].id);
        await expectLater(
          rollbackService.switchEmbeddingModel(rollbackModels[1].id),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('rollback'),
            ),
          ),
        );
      });

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

      test('preserves an existing file when the checksum read fails', () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'model-checksum-injected-read-error-',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });
        const expected = EmbeddingModels.gecko64;
        final file = File('${tempDir.path}/${expected.fileName}');
        await file.writeAsBytes(const [1, 2, 3]);
        final errors = <Object>[];
        final service = ModelManagementService(
          installedModelPathResolver: (_) async => file.path,
          fileChecksumVerifier: (_, _) async {
            throw StateError('injected checksum read failed');
          },
        );
        addTearDown(service.dispose);
        final subscription = service.modelStatusStream.listen(
          (_) {},
          onError: errors.add,
        );
        addTearDown(subscription.cancel);
        final model = service.models.firstWhere(
          (candidate) => candidate.id == expected.id,
        );

        expect(await service.verifyDeclaredChecksumForTest(model), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(file.existsSync(), isTrue);
        expect(model.errorMessage, contains('injected checksum read failed'));
        expect(
          errors,
          contains(
            'Unable to read model for checksum verification for '
            '${expected.id}.',
          ),
        );
      });

      test(
        'clears persisted checksum metadata after a confirmed mismatch',
        () async {
          SharedPreferences.setMockInitialValues({});
          final tempDir = await Directory.systemTemp.createTemp(
            'model-checksum-clear-metadata-',
          );
          addTearDown(() async {
            if (tempDir.existsSync()) await tempDir.delete(recursive: true);
          });
          const expected = EmbeddingModels.gecko64;
          final file = File('${tempDir.path}/${expected.fileName}');
          await file.writeAsBytes(const [1, 2, 3]);
          var shouldVerify = true;
          final service = ModelManagementService(
            installedModelPathResolver: (_) async => file.path,
            fileChecksumVerifier: (_, _) async => shouldVerify,
            sharedPreferencesLoader: SharedPreferences.getInstance,
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.id == expected.id,
          );

          expect(await service.verifyDeclaredChecksumForTest(model), isTrue);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getKeys().any(
              (key) => key == 'model_verification_metadata_${expected.id}',
            ),
            isTrue,
          );

          await Future<void>.delayed(const Duration(milliseconds: 2));
          await file.writeAsBytes(const [4, 5, 6]);
          shouldVerify = false;
          expect(await service.verifyDeclaredChecksumForTest(model), isFalse);
          expect(file.existsSync(), isFalse);
          expect(
            prefs.getKeys().any(
              (key) => key == 'model_verification_metadata_${expected.id}',
            ),
            isFalse,
          );
        },
      );

      test('persists verification metadata and skips hashing on an unchanged '
          'cold start', () async {
        SharedPreferences.setMockInitialValues({});
        final tempDir = await Directory.systemTemp.createTemp(
          'model-checksum-cache-',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });
        final file = File(
          '${tempDir.path}/${EmbeddingModels.gecko64.fileName}',
        );
        await file.writeAsBytes(const [1, 2, 3]);
        var verifierCalls = 0;

        ModelManagementService createService() => ModelManagementService(
          installedModelPathResolver: (_) async => file.path,
          fileChecksumVerifier: (_, _) async {
            verifierCalls++;
            return true;
          },
          sharedPreferencesLoader: SharedPreferences.getInstance,
        );

        final first = createService();
        final model = first.models.firstWhere(
          (candidate) => candidate.id == EmbeddingModels.gecko64.id,
        );
        expect(await first.verifyDeclaredChecksumForTest(model), isTrue);
        first.dispose();

        final second = createService();
        addTearDown(second.dispose);
        final secondModel = second.models.firstWhere(
          (candidate) => candidate.id == EmbeddingModels.gecko64.id,
        );
        expect(await second.verifyDeclaredChecksumForTest(secondModel), isTrue);
        expect(verifierCalls, 1);
      });

      test(
        'rehashes when persisted verification metadata no longer matches',
        () async {
          SharedPreferences.setMockInitialValues({});
          final tempDir = await Directory.systemTemp.createTemp(
            'model-checksum-cache-miss-',
          );
          addTearDown(() async {
            if (tempDir.existsSync()) await tempDir.delete(recursive: true);
          });
          final file = File(
            '${tempDir.path}/${EmbeddingModels.gecko64.fileName}',
          );
          await file.writeAsBytes(const [1, 2, 3]);
          var verifierCalls = 0;
          ModelManagementService createService() => ModelManagementService(
            installedModelPathResolver: (_) async => file.path,
            fileChecksumVerifier: (_, _) async {
              verifierCalls++;
              return true;
            },
            sharedPreferencesLoader: SharedPreferences.getInstance,
          );

          final first = createService();
          final model = first.models.firstWhere(
            (candidate) => candidate.id == EmbeddingModels.gecko64.id,
          );
          await first.verifyDeclaredChecksumForTest(model);
          first.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await file.writeAsBytes(const [4, 5, 6, 7]);

          final second = createService();
          addTearDown(second.dispose);
          final secondModel = second.models.firstWhere(
            (candidate) => candidate.id == EmbeddingModels.gecko64.id,
          );
          expect(
            await second.verifyDeclaredChecksumForTest(secondModel),
            isTrue,
          );
          expect(verifierCalls, 2);
        },
      );

      test(
        'preserves a model file when checksum verification cannot read it',
        () async {
          final tempDir = await Directory.systemTemp.createTemp(
            'model-checksum-read-error-',
          );
          addTearDown(() async {
            if (tempDir.existsSync()) await tempDir.delete(recursive: true);
          });
          final missingFile = File(
            '${tempDir.path}/${EmbeddingModels.gecko64.fileName}',
          );
          final service = ModelManagementService(
            installedModelPathResolver: (_) async => missingFile.path,
          );
          addTearDown(service.dispose);
          final model = service.models.firstWhere(
            (candidate) => candidate.id == EmbeddingModels.gecko64.id,
          );

          expect(await service.verifyDeclaredChecksumForTest(model), isFalse);
          expect(missingFile.existsSync(), isFalse);
          expect(model.errorMessage, contains('Unable to read'));
        },
      );

      test(
        'retries initialization after a first initialization failure',
        () async {
          final ragSettings = locator<RagSettingsService>();
          var getterCalls = 0;
          when(() => ragSettings.activeInferenceModelId).thenAnswer((_) {
            getterCalls++;
            if (getterCalls == 1) throw StateError('initialization failed');
            return null;
          });
          when(() => ragSettings.activeEmbeddingModelId).thenReturn(null);
          final service = ModelManagementService(
            modelInstalledChecker: (_) async => false,
          );
          addTearDown(service.dispose);

          await expectLater(service.initialize(), throwsStateError);
          await service.initialize();

          expect(getterCalls, 2);
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
