import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  group('StartupViewModel Tests -', () {
    setUp(registerTestHelpers);
    tearDown(unregisterTestHelpers);

    group('runStartupLogic -', () {
      test(
        'Should call initialize on ModelManagementService during startup',
        () async {
          final mockService = getAndRegisterMockModelManagementService();
          final viewModel = StartupViewModel();

          await viewModel.runStartupLogic();
          verify(mockService.initialize).called(1);
        },
      );

      test(
        'Should navigate to ChatView when both models are downloaded',
        () async {
          final mockNavigation = getAndRegisterMockNavigationService();
          final mockService = getAndRegisterMockModelManagementService();

          final inferenceModel = ModelInfo(
            id: '1',
            name: 'Inference',
            url: 'url',
            type: AppModelType.inference,
            status: ModelStatus.downloaded,
          );
          final embeddingModel = ModelInfo(
            id: '2',
            name: 'Embedding',
            url: 'url',
            type: AppModelType.embedding,
            status: ModelStatus.downloaded,
          );

          when(() => mockService.models).thenReturn([
            inferenceModel,
            embeddingModel,
          ]);

          final viewModel = StartupViewModel();
          await viewModel.runStartupLogic();

          // Wait for potential delays
          await Future<void>.delayed(const Duration(milliseconds: 600));

          verify(mockNavigation.replaceWithChatView).called(1);
        },
      );

      test(
        'Should go to SettingsView when inference model is NOT downloaded',
        () async {
          final mockNavigation = getAndRegisterMockNavigationService();
          final mockService = getAndRegisterMockModelManagementService();

          final inferenceModel = ModelInfo(
            id: '1',
            name: 'Inference',
            url: 'url',
            type: AppModelType.inference,
          );
          final embeddingModel = ModelInfo(
            id: '2',
            name: 'Embedding',
            url: 'url',
            type: AppModelType.embedding,
            status: ModelStatus.downloaded,
          );

          when(() => mockService.models).thenReturn([
            inferenceModel,
            embeddingModel,
          ]);

          final viewModel = StartupViewModel();
          await viewModel.runStartupLogic();

          verify(mockNavigation.replaceWithSettingsView).called(1);
        },
      );

      test(
        'Should go to SettingsView when embedding model is NOT downloaded',
        () async {
          final mockNavigation = getAndRegisterMockNavigationService();
          final mockService = getAndRegisterMockModelManagementService();

          final inferenceModel = ModelInfo(
            id: '1',
            name: 'Inference',
            url: 'url',
            type: AppModelType.inference,
            status: ModelStatus.downloaded,
          );
          final embeddingModel = ModelInfo(
            id: '2',
            name: 'Embedding',
            url: 'url',
            type: AppModelType.embedding,
          );

          when(() => mockService.models).thenReturn([
            inferenceModel,
            embeddingModel,
          ]);

          final viewModel = StartupViewModel();
          await viewModel.runStartupLogic();

          verify(mockNavigation.replaceWithSettingsView).called(1);
        },
      );
    });
  });
}
