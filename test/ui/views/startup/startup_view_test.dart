import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  group('StartupView Widget Tests -', () {
    setUp(registerTestHelpers);
    tearDown(unregisterTestHelpers);

    testWidgets('Initializes with loading text and indicator', (tester) async {
      getAndRegisterMockModelManagementService();

      await tester.pumpWidget(const MaterialApp(home: StartupView()));

      expect(find.text('Initializing AI Models...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Shows error and retry button when initialization fails', (
      tester,
    ) async {
      final mockService = getAndRegisterMockModelManagementService();
      when(
        mockService.initialize,
      ).thenThrow(Exception('Failed to load'));

      await tester.pumpWidget(const MaterialApp(home: StartupView()));
      await tester.pump(); // Allow onViewModelReady to run

      // Status message might be updated via stream or exception
      // Since it's caught in runStartupLogic
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Error: Exception: Failed to load'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
