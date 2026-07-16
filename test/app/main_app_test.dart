import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/main_app.dart';
import 'package:offline_sync/services/vector_store.dart';

import '../helpers/test_helpers.dart';

void main() {
  tearDown(unregisterTestHelpers);

  testWidgets('AppLifecycleRoot closes VectorStore on detached lifecycle', (
    tester,
  ) async {
    final mockVectorStore = MockVectorStore();
    when(mockVectorStore.close).thenReturn(null);
    locator.registerSingleton<VectorStore>(mockVectorStore);

    await tester.pumpWidget(
      const AppLifecycleRoot(
        child: MaterialApp(home: SizedBox()),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    verify(mockVectorStore.close).called(1);
  });
}
