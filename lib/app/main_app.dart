import 'dart:async';

import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/app/app_theme.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:stacked_services/stacked_services.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleRoot(
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: Routes.startupView,
        onGenerateRoute: StackedRouter().onGenerateRoute,
        navigatorKey: StackedService.navigatorKey,
      ),
    );
  }
}

class AppLifecycleRoot extends StatefulWidget {
  const AppLifecycleRoot({required this.child, this.onDetached, super.key});

  final Widget child;
  final VoidCallback? onDetached;

  @override
  State<AppLifecycleRoot> createState() => _AppLifecycleRootState();
}

class _AppLifecycleRootState extends State<AppLifecycleRoot> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onPause: () {
        if (locator.isRegistered<InferenceModelProvider>()) {
          unawaited(locator<InferenceModelProvider>().releaseModel());
        }
      },
      onDetach: () {
        widget.onDetached?.call();
        if (locator.isRegistered<VectorStore>()) {
          unawaited(locator<VectorStore>().close());
        }
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
