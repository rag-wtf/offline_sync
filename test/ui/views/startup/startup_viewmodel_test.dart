import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  group('StartupViewModel Tests -', () {
    setUp(registerTestHelpers);
    tearDown(unregisterTestHelpers);

    group('Basic initialization -', () {
      test('Should instantiate without errors', () {
        final viewModel = StartupViewModel();
        expect(viewModel, isNotNull);
        expect(viewModel.statusMessage, isNull);
        expect(viewModel.needsToken, isFalse);
      });

      test('Should handle errors gracefully', () async {
        getAndRegisterMockModelManagementService();
        getAndRegisterMockRagSettingsService();
        getAndRegisterMockNavigationService();

        // Simulate error during device capability check by not mocking it
        final viewModel = StartupViewModel();

        // Running startup logic will fail at device capability check
        // but should catch the error gracefully
        await viewModel.runStartupLogic();

        // The viewModel should have set an error
        expect(viewModel.hasError, isTrue);
      });
    });
  });
}
