// Ignore for testing purposes
// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.dart';

void main() {
  group('App', () {
    testWidgets('renders MainPage', (tester) async {
      await tester.pumpWidget(App());
      expect(find.text('Hello World'), findsOneWidget);
    });
  });
}
