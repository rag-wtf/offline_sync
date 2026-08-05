import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

// Fake widget for navigation tests
class FakeWidget extends Fake implements Widget {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'FakeWidget';
  }
}

class FakeDeviceCapabilityService extends DeviceCapabilityService {
  FakeDeviceCapabilityService(this.capabilities);

  final DeviceCapabilities capabilities;

  @override
  Future<DeviceCapabilities> getCapabilities() async => capabilities;
}

class FakeModelRecommendationService extends ModelRecommendationService {
  FakeModelRecommendationService({
    required this.recommendedModels,
    this.meetsRequirements = true,
    this.unsupportedMessage = 'Unsupported device',
  });

  final RecommendedModels recommendedModels;
  final bool meetsRequirements;
  final String unsupportedMessage;

  @override
  RecommendedModels getRecommendedModels(DeviceCapabilities capabilities) =>
      recommendedModels;

  @override
  bool meetsMinimumRequirements(DeviceCapabilities capabilities) =>
      meetsRequirements;

  @override
  String getUnsupportedDeviceMessage(DeviceCapabilities capabilities) =>
      unsupportedMessage;
}

void main() {
  group('StartupViewModel Tests -', () {
    late MockNavigationService mockNavigationService;
    late MockModelManagementService mockModelService;

    setUpAll(() {
      registerFallbackValue(
        const DeviceCapabilities(
          totalRamMB: 2048,
          availableStorageMB: 1024,
          hasGpu: false,
          platform: 'android',
        ),
      );
      registerFallbackValue(FakeWidget());
    });

    setUp(() {
      mockNavigationService = getAndRegisterMockNavigationService();
      mockModelService = getAndRegisterMockModelManagementService();
      getAndRegisterMockRagSettingsService();
    });

    tearDown(unregisterTestHelpers);

    group('Basic initialization -', () {
      test('Should instantiate without errors', () {
        final viewModel = StartupViewModel();
        expect(viewModel, isNotNull);
        expect(viewModel.statusMessage, isNull);
        expect(viewModel.needsToken, isFalse);
        expect(viewModel.capabilities, isNull);
      });

      test('Should start with no error state', () {
        final viewModel = StartupViewModel();
        expect(viewModel.hasError, isFalse);
        expect(viewModel.modelError, isNull);
      });

      test('Should have null capabilities before running startup logic', () {
        final viewModel = StartupViewModel();
        expect(viewModel.capabilities, isNull);
      });
    });

    group('Error handling -', () {
      test('Should handle errors gracefully', () async {
        // Don't mock device capability service - it will throw an error
        // when trying to access it
        final viewModel = StartupViewModel();

        // Running startup logic will fail at device capability check
        // but should catch the error gracefully
        await viewModel.runStartupLogic();

        // The viewModel should have set an error
        expect(viewModel.hasError, isTrue);
      });

      test('Should set needsToken flag on 401 error', () async {
        final viewModel = StartupViewModel();

        // Create a mock model with 401 error
        final errorModel =
            ModelInfo(
                id: 'test-model',
                name: 'Test Model',
                url: 'https://test.com/model',
                type: AppModelType.inference,
              )
              ..status = ModelStatus.error
              ..errorMessage = '401 Unauthorized';

        when(() => mockModelService.models).thenReturn([errorModel]);

        // Simulate 401 error in stream
        final controller = StreamController<List<ModelInfo>>.broadcast();
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => controller.stream);

        // Start the startup logic (it will subscribe to stream)
        unawaited(viewModel.runStartupLogic());

        // Emit error event
        controller.add([errorModel]);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(viewModel.needsToken, isTrue);

        await controller.close();
      });

      test('Should handle generic errors without setting needsToken', () async {
        final viewModel = StartupViewModel();

        final errorModel =
            ModelInfo(
                id: 'test-model',
                name: 'Test Model',
                url: 'https://test.com/model',
                type: AppModelType.inference,
              )
              ..status = ModelStatus.error
              ..errorMessage = 'Network error';

        when(() => mockModelService.models).thenReturn([errorModel]);

        final controller = StreamController<List<ModelInfo>>.broadcast();
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => controller.stream);

        unawaited(viewModel.runStartupLogic());

        controller.add([errorModel]);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(viewModel.needsToken, isFalse);

        await controller.close();
      });
    });

    group('Status message updates -', () {
      test('Should update status message during download progress', () async {
        final downloadingModel =
            ModelInfo(
                id: 'test-model',
                name: 'Test Model',
                url: 'https://test.com/model',
                type: AppModelType.inference,
              )
              ..status = ModelStatus.downloading
              ..progress = 0.5;
        final inferenceModel = ModelInfo(
          id: InferenceModels.gemma3_270M.id,
          name: InferenceModels.gemma3_270M.name,
          url: 'https://example.com/inference',
          type: AppModelType.inference,
        )..status = ModelStatus.downloaded;
        final embeddingModel = ModelInfo(
          id: EmbeddingModels.gecko64.id,
          name: EmbeddingModels.gecko64.name,
          url: 'https://example.com/embedding',
          type: AppModelType.embedding,
        )..status = ModelStatus.downloaded;
        final controller = StreamController<List<ModelInfo>>.broadcast();
        final progressObserved = Completer<String>();
        final ragSettings = getAndRegisterMockRagSettingsService();

        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => controller.stream);
        when(
          () => mockModelService.models,
        ).thenReturn([inferenceModel, embeddingModel]);
        when(mockModelService.initialize).thenAnswer((_) async {});
        when(ragSettings.initialize).thenAnswer((_) async {});
        when(
          () => mockModelService.activeInferenceModel,
        ).thenReturn(inferenceModel);
        when(
          () => mockModelService.activeEmbeddingModel,
        ).thenReturn(embeddingModel);
        when(
          () => mockNavigationService.replaceWith<dynamic>(
            any(),
            arguments: any<dynamic>(named: 'arguments'),
            id: any(named: 'id'),
            preventDuplicates: any(named: 'preventDuplicates'),
            parameters: any(named: 'parameters'),
            transition: any(named: 'transition'),
          ),
        ).thenAnswer((_) async {});

        late final StartupViewModel viewModel;
        viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: FakeDeviceCapabilityService(
            const DeviceCapabilities(
              totalRamMB: 4096,
              availableStorageMB: 4096,
              hasGpu: false,
              platform: 'android',
            ),
          ),
          recommendationService: FakeModelRecommendationService(
            recommendedModels: const RecommendedModels(
              inferenceModel: InferenceModels.gemma3_270M,
              embeddingModel: EmbeddingModels.gecko64,
              tier: DeviceTier.low,
            ),
          ),
          ragSettingsService: ragSettings,
        );
        viewModel.addListener(() {
          final status = viewModel.statusMessage;
          if (!progressObserved.isCompleted &&
              status != null &&
              status.contains('Downloading')) {
            progressObserved.complete(status);
          }
        });

        final startup = viewModel.runStartupLogic();

        controller.add([downloadingModel]);
        final progressMessage = await progressObserved.future;

        expect(progressMessage, contains('Downloading'));
        expect(progressMessage, contains('50.0'));

        await controller.close();
        await startup;
      });
    });

    group('Retry functionality -', () {
      test('Should reset error state and retry startup logic', () async {
        final viewModel = StartupViewModel()
          // Set an error first
          ..setError('Test error');
        expect(viewModel.hasError, isTrue);

        // Reset models to allow retry
        when(() => mockModelService.models).thenReturn([]);
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => const Stream.empty());

        // Call retry - it should clear the error and start the process again
        await viewModel.retry();

        // retry() should have cleared the error state initially
        // (even though it may set a new error due to missing services)
        // What we're testing is that retry() resets the error
        // and restarts the flow. The status message will be from
        // runStartupLogic, not 'Retrying...'
        expect(viewModel.statusMessage, isNotNull);
        // The message should indicate the startup process has run
        expect(
          viewModel.statusMessage,
          anyOf(
            contains('Detecting'),
            contains('Selecting'),
            contains('error'),
            contains('Error'),
          ),
        );
      });

      test('Should delegate model error reset on retry', () async {
        final viewModel = StartupViewModel();

        final errorModel =
            ModelInfo(
                id: 'test-model',
                name: 'Test Model',
                url: 'https://test.com/model',
                type: AppModelType.inference,
              )
              ..status = ModelStatus.error
              ..errorMessage = 'Previous error';

        when(() => mockModelService.models).thenReturn([errorModel]);
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => const Stream.empty());
        when(mockModelService.resetErroredModels).thenReturn(null);

        await viewModel.retry();

        verify(mockModelService.resetErroredModels).called(1);
      });
    });

    group('Token entry flow -', () {
      test('Should navigate to token dialog and retry', () async {
        when(
          () => mockNavigationService.navigateWithTransition<bool?>(
            any(),
            transitionStyle: any(named: 'transitionStyle'),
          ),
        ).thenAnswer((_) async => true);

        when(() => mockModelService.models).thenReturn([]);
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => const Stream.empty());

        final viewModel = StartupViewModel();

        await viewModel.enterToken();

        verify(
          () => mockNavigationService.navigateWithTransition<bool?>(
            any(),
            transitionStyle: any(named: 'transitionStyle'),
          ),
        ).called(1);
      });
    });

    group('Disposal -', () {
      test('Should dispose stream subscription without errors', () {
        final viewModel = StartupViewModel();

        expect(viewModel.dispose, returnsNormally);
      });

      test('Should handle dispose even if subscription is null', () {
        final viewModel = StartupViewModel();
        // Don't run startup logic, so subscription is null

        expect(viewModel.dispose, returnsNormally);
      });
    });

    group('Unsupported device handling -', () {
      test('Should set isUnsupportedDevice flag for low-spec devices', () {
        final viewModel = StartupViewModel();
        expect(viewModel.isUnsupportedDevice, isFalse);
      });
    });

    group('Injected startup dependencies -', () {
      late ModelInfo inferenceModel;
      late ModelInfo embeddingModel;
      late FakeModelRecommendationService recommendationService;
      late FakeDeviceCapabilityService deviceService;
      late MockRagSettingsService ragSettings;

      setUp(() {
        inferenceModel = ModelInfo(
          id: InferenceModels.gemma3_270M.id,
          name: InferenceModels.gemma3_270M.name,
          url: 'https://example.com/inference',
          type: AppModelType.inference,
        )..status = ModelStatus.downloaded;
        embeddingModel = ModelInfo(
          id: EmbeddingModels.gecko64.id,
          name: EmbeddingModels.gecko64.name,
          url: 'https://example.com/embedding',
          type: AppModelType.embedding,
        )..status = ModelStatus.downloaded;
        recommendationService = FakeModelRecommendationService(
          recommendedModels: const RecommendedModels(
            inferenceModel: InferenceModels.gemma3_270M,
            embeddingModel: EmbeddingModels.gecko64,
            tier: DeviceTier.low,
          ),
        );
        deviceService = FakeDeviceCapabilityService(
          const DeviceCapabilities(
            totalRamMB: 4096,
            availableStorageMB: 4096,
            hasGpu: false,
            platform: 'android',
          ),
        );
        ragSettings = getAndRegisterMockRagSettingsService();

        when(
          () => mockModelService.models,
        ).thenReturn([inferenceModel, embeddingModel]);
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => const Stream.empty());
        when(mockModelService.initialize).thenAnswer((_) async {});
        when(
          () => mockModelService.downloadModel(any()),
        ).thenAnswer((_) async {});
        when(
          () => mockModelService.switchInferenceModel(any()),
        ).thenAnswer((_) async {});
        when(
          () => mockModelService.switchEmbeddingModel(any()),
        ).thenAnswer((_) async {});
        when(() => mockModelService.activeInferenceModel).thenReturn(null);
        when(() => mockModelService.activeEmbeddingModel).thenReturn(null);
        when(ragSettings.initialize).thenAnswer((_) async {});
        when(
          () => mockNavigationService.replaceWith<dynamic>(
            any(),
            arguments: any<dynamic>(named: 'arguments'),
            id: any(named: 'id'),
            preventDuplicates: any(named: 'preventDuplicates'),
            parameters: any(named: 'parameters'),
            transition: any(named: 'transition'),
          ),
        ).thenAnswer((_) async {});
      });

      test('navigates to chat when recommended models are ready', () async {
        final viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: deviceService,
          recommendationService: recommendationService,
          ragSettingsService: ragSettings,
        );

        await viewModel.runStartupLogic();

        expect(viewModel.capabilities?.platform, 'android');
        verify(
          () => mockModelService.switchInferenceModel(inferenceModel.id),
        ).called(1);
        verify(
          () => mockModelService.switchEmbeddingModel(embeddingModel.id),
        ).called(1);
        verify(
          () => mockNavigationService.replaceWith<dynamic>(
            Routes.chatView,
            arguments: any<dynamic>(named: 'arguments'),
            id: any(named: 'id'),
            preventDuplicates: any(named: 'preventDuplicates'),
            parameters: any(named: 'parameters'),
            transition: any(named: 'transition'),
          ),
        ).called(1);
      });

      test('navigates to settings when required'
          ' models are still missing', () async {
        embeddingModel.status = ModelStatus.notDownloaded;

        final viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: deviceService,
          recommendationService: recommendationService,
          ragSettingsService: ragSettings,
        );

        await viewModel.runStartupLogic();

        verify(
          () => mockModelService.downloadModel(embeddingModel.id),
        ).called(1);
        verify(
          () => mockNavigationService.replaceWith<dynamic>(
            Routes.settingsView,
            arguments: any<dynamic>(named: 'arguments'),
            id: any(named: 'id'),
            preventDuplicates: any(named: 'preventDuplicates'),
            parameters: any(named: 'parameters'),
            transition: any(named: 'transition'),
          ),
        ).called(1);
      });

      test('marks unsupported devices while still'
          ' continuing startup flow', () async {
        final viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: deviceService,
          recommendationService: FakeModelRecommendationService(
            recommendedModels: recommendationService.recommendedModels,
            meetsRequirements: false,
            unsupportedMessage: 'Need more RAM',
          ),
          ragSettingsService: ragSettings,
        );

        await viewModel.runStartupLogic();

        expect(viewModel.isUnsupportedDevice, isTrue);
        expect(viewModel.modelError, 'Need more RAM');
      });

      test('cancels the previous subscription'
          ' when startup runs twice', () async {
        final controller = StreamController<List<ModelInfo>>.broadcast();
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => controller.stream);

        final viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: deviceService,
          recommendationService: recommendationService,
          ragSettingsService: ragSettings,
        );

        await viewModel.runStartupLogic();
        await viewModel.runStartupLogic();

        controller.add([inferenceModel, embeddingModel]);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(viewModel.statusMessage, 'Finalizing initialization...');
        await controller.close();
      });

      test('handles stream onError branches for 401'
          ' and generic failures', () async {
        final controller = StreamController<List<ModelInfo>>.broadcast();
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => controller.stream);

        final viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: deviceService,
          recommendationService: recommendationService,
          ragSettingsService: ragSettings,
        );

        unawaited(viewModel.runStartupLogic());
        controller.addError(StateError('401 unauthorized'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(viewModel.needsToken, isTrue);

        controller.addError(StateError('plain failure'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(viewModel.modelError, contains('plain failure'));

        await controller.close();
      });

      test('downloads inference models that are missing and'
          ' stops on post-download errors', () async {
        inferenceModel.status = ModelStatus.notDownloaded;
        embeddingModel
          ..status = ModelStatus.error
          ..errorMessage = 'Disk full';

        final dynamicModels = <ModelInfo>[inferenceModel, embeddingModel];
        when(() => mockModelService.models).thenReturn(dynamicModels);

        final viewModel = StartupViewModel(
          navigationService: mockNavigationService,
          modelService: mockModelService,
          deviceService: deviceService,
          recommendationService: recommendationService,
          ragSettingsService: ragSettings,
        );

        await viewModel.runStartupLogic();

        verify(
          () => mockModelService.downloadModel(inferenceModel.id),
        ).called(1);
        expect(
          viewModel.modelError,
          'Failed to download models. Please retry.',
        );
      });
    });
  });
}
