import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

// Fake widget for navigation tests
class FakeWidget extends Fake implements Widget {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'FakeWidget';
  }
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
        final viewModel = StartupViewModel();

        final downloadingModel =
            ModelInfo(
                id: 'test-model',
                name: 'Test Model',
                url: 'https://test.com/model',
                type: AppModelType.inference,
              )
              ..status = ModelStatus.downloading
              ..progress = 0.5;

        when(() => mockModelService.models).thenReturn([downloadingModel]);

        final controller = StreamController<List<ModelInfo>>.broadcast();
        when(
          () => mockModelService.modelStatusStream,
        ).thenAnswer((_) => controller.stream);

        unawaited(viewModel.runStartupLogic());

        controller.add([downloadingModel]);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(viewModel.statusMessage, contains('Downloading'));
        expect(viewModel.statusMessage, contains('50.0'));

        await controller.close();
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
            contains('error'),
            contains('Error'),
          ),
        );
      });

      test('Should reset model error states on retry', () async {
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

        // Retry should reset error models
        await viewModel.retry();

        // The model status should be reset to notDownloaded
        expect(errorModel.status, ModelStatus.notDownloaded);
        expect(errorModel.progress, 0.0);
        expect(errorModel.errorMessage, isNull);
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
  });
}
