import 'dart:async';
import 'dart:ui' show AppExitResponse;

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
      onDetach: _handleDetach,
      onExitRequested: _handleExitRequested,
    );
  }

  void _handleDetach() {
    widget.onDetached?.call();
    // AppLifecycleListener.onDetach is synchronous. Observe the fallback
    // close explicitly because the framework cannot await this callback.
    _observeShutdown(_closeVectorStore());
  }

  Future<AppExitResponse> _handleExitRequested() async {
    try {
      await _closeVectorStore();
      return AppExitResponse.exit;
    } on Object catch (error, stackTrace) {
      _reportShutdownFailure(error, stackTrace);
      return AppExitResponse.cancel;
    }
  }

  Future<void> _closeVectorStore() async {
    if (locator.isRegistered<VectorStore>()) {
      await locator<VectorStore>().close();
    }
  }

  void _observeShutdown(Future<void> shutdown) {
    shutdown
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _reportShutdownFailure(error, stackTrace);
          },
        )
        .ignore();
  }

  void _reportShutdownFailure(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app lifecycle shutdown',
        context: ErrorDescription('while closing persistent storage'),
      ),
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
