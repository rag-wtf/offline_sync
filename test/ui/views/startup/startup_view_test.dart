import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  group('StartupView Widget Tests -', () {
    setUp(registerTestHelpers);
    tearDown(unregisterTestHelpers);

    testWidgets('Initializes with loading text and indicator', (tester) async {
      getAndRegisterMockModelManagementService();
      getAndRegisterMockRagSettingsService();

      await tester.pumpWidget(const MaterialApp(home: StartupView()));

      expect(find.text('Initializing AI Models...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
