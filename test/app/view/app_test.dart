// Ignore for testing purposes

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/main_app.dart';

void main() {
  setUpAll(() async {
    await setupLocator();
  });

  group('App', () {
    testWidgets('renders ChatView', (tester) async {
      await tester.pumpWidget(const MainApp());
      await tester.pump(); // Allow for initial transition/build
      expect(find.text('RAG Sync Chat'), findsOneWidget);
    });
  });
}
