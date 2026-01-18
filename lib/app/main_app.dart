import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/app/app_theme.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:stacked_services/stacked_services.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline RAG Sync',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: Routes.startupView,
      onGenerateRoute: StackedRouter().onGenerateRoute,
      navigatorKey: StackedService.navigatorKey,
    );
  }
}
