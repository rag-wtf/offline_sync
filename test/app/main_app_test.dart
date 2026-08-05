import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/app/main_app.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:stacked_services/stacked_services.dart';

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
      const AppLifecycleRoot(child: MaterialApp(home: SizedBox())),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    verify(mockVectorStore.close).called(1);
  });

  testWidgets('MainApp wires MaterialApp shell with router and localization', (
    tester,
  ) async {
    registerTestHelpers();
    final modelService = locator<ModelManagementService>();
    final settingsService = locator<RagSettingsService>();

    when(
      () => modelService.modelStatusStream,
    ).thenAnswer((_) => const Stream<List<ModelInfo>>.empty());
    when(modelService.initialize).thenAnswer((_) async {});
    when(() => modelService.models).thenReturn(const <ModelInfo>[]);
    when(() => modelService.activeInferenceModel).thenReturn(null);
    when(() => modelService.activeEmbeddingModel).thenReturn(null);
    when(settingsService.initialize).thenAnswer((_) async {});

    await tester.pumpWidget(const MainApp());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp.initialRoute, Routes.startupView);
    expect(materialApp.navigatorKey, StackedService.navigatorKey);
    expect(materialApp.theme, isNotNull);
    expect(materialApp.darkTheme, isNotNull);
    expect(materialApp.supportedLocales, AppLocalizations.supportedLocales);
    expect(
      materialApp.localizationsDelegates,
      AppLocalizations.localizationsDelegates,
    );
    expect(materialApp.onGenerateTitle, isNotNull);
  });

  testWidgets('BuildContext.l10n returns generated localizations', (
    tester,
  ) async {
    AppLocalizations? localizations;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            localizations = context.l10n;
            return Text(context.l10n.appTitle);
          },
        ),
      ),
    );

    expect(localizations, isNotNull);
    expect(find.text(localizations!.appTitle), findsOneWidget);
  });

  testWidgets(
    'AppLifecycleRoot handles detach without a registered VectorStore',
    (tester) async {
      await tester.pumpWidget(
        const AppLifecycleRoot(child: MaterialApp(home: SizedBox())),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();

      expect(find.byType(SizedBox), findsOneWidget);
    },
  );

  testWidgets('AppLifecycleRoot invokes custom onDetached callback', (
    tester,
  ) async {
    var detached = 0;

    await tester.pumpWidget(
      AppLifecycleRoot(
        onDetached: () => detached++,
        child: const MaterialApp(home: SizedBox()),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    expect(detached, 1);
  });
}
