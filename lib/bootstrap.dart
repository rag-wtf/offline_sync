import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/bootstrap_mobile.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart'
    as platform;
import 'package:offline_sync/l10n/l10n.dart';
import 'package:offline_sync/services/environment_service.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/ui/setup_dialog_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const notificationPermissionRequestAttemptedKey =
    'notification_permission_request_attempted';

Future<void> bootstrap(
  FutureOr<Widget> Function() builder, {
  required String flavor,
  bool? isWebOverride,
  TargetPlatform? targetPlatformOverride,
  Future<void> Function()? flutterGemmaInitialize,
  Future<void> Function()? initializeSqliteOverride,
  Future<void> Function()? setupLocatorOverride,
  void Function()? setupDialogUiOverride,
  EnvironmentService? environmentServiceOverride,
  void Function(Widget app)? runAppOverride,
  Future<void> Function()? requestNotificationPermissionOverride,
  Future<void> Function()? configureDownloaderOverride,
  void Function()? configureDownloaderNotificationOverride,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final isWeb = isWebOverride ?? kIsWeb;
  final targetPlatform = targetPlatformOverride ?? defaultTargetPlatform;
  final runAppFn = runAppOverride ?? runApp;
  LoggingService.configureFlavor(flavor);

  // These handlers must be installed before plugin, database, or locator
  // setup. A failure during startup must be recorded and rendered instead of
  // leaving a blank screen.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      _recordCrashSafely(
        'Unhandled Flutter framework error',
        error: details.exception,
        stackTrace: details.stack,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      _recordCrashSafely(
        'Unhandled platform error',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    return true;
  };

  try {
    // Configure FileDownloader for foreground mode on Android to prevent
    // WorkManager from cancelling downloads on network state changes. This must
    // be called before FlutterGemma.initialize() which uses the downloader.
    // IMPORTANT: Foreground mode requires a notification to be configured!
    if (!isWeb && targetPlatform == TargetPlatform.android) {
      // Configure foreground mode for files >= 0 MB (all files)
      if (configureDownloaderOverride != null) {
        await configureDownloaderOverride();
      } else {
        // coverage:ignore-start
        await FileDownloader().configure(
          androidConfig: (Config.runInForegroundIfFileLargerThan, 0),
        );
        // coverage:ignore-end
      }

      // Configure notification for the 'smart_downloads' group used by
      // SmartDownloader. Without a 'running' notification, foreground mode is
      // ignored!
      if (configureDownloaderNotificationOverride != null) {
        configureDownloaderNotificationOverride();
      } else {
        // coverage:ignore-start
        FileDownloader().configureNotificationForGroup(
          'smart_downloads',
          running: const TaskNotification(
            'Downloading Model',
            '{displayName} - {progress}%',
          ),
          progressBar: true,
        );
        // coverage:ignore-end
      }

      // Android 13+ requires a runtime grant for notification visibility.
      // Downloads still run in the foreground if the permission is denied, so
      // Progress notifications are best-effort rather than required for
      // success.
      unawaited(
        requestNotificationPermissionOverride?.call() ??
            // coverage:ignore-start
            _requestAndroidNotificationPermissionIfNeeded(),
        // coverage:ignore-end
      );
    }

    await (flutterGemmaInitialize ??
        () => FlutterGemma.initialize(
          inferenceEngines: const [
            LiteRtLmEngine(),
            MediaPipeEngine(),
          ],
          embeddingBackends: const [
            LiteRtEmbeddingBackend(),
          ],
        ))();

    // Platform-specific SQLite initialization
    await (initializeSqliteOverride ?? platform.initializeSqlite)();

    await (setupLocatorOverride ?? setupLocator)();
    (setupDialogUiOverride ?? setupDialogUi)();
    (environmentServiceOverride ?? locator<EnvironmentService>()).flavor =
        flavor;

    runAppFn(await builder());
  } on Object catch (error, stackTrace) {
    await _recordCrashSafely(
      'Bootstrap initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
    // A failed initialization may have left lazy singletons, platform
    // services, or partially constructed app dependencies registered. Reset
    // the locator before exposing Retry so the next attempt rebuilds a clean
    // dependency graph and disposes any resources created during this one.
    await _resetLocatorSafely();
    runAppFn(
      _BootstrapFailureApp(
        error: error,
        onRetry: () => bootstrap(
          builder,
          flavor: flavor,
          isWebOverride: isWebOverride,
          targetPlatformOverride: targetPlatformOverride,
          flutterGemmaInitialize: flutterGemmaInitialize,
          initializeSqliteOverride: initializeSqliteOverride,
          setupLocatorOverride: setupLocatorOverride,
          setupDialogUiOverride: setupDialogUiOverride,
          environmentServiceOverride: environmentServiceOverride,
          runAppOverride: runAppOverride,
          requestNotificationPermissionOverride:
              requestNotificationPermissionOverride,
          configureDownloaderOverride: configureDownloaderOverride,
          configureDownloaderNotificationOverride:
              configureDownloaderNotificationOverride,
        ),
      ),
    );
  }
}

Future<void> _resetLocatorSafely() async {
  try {
    await locator.reset();
  } on Object catch (error, stackTrace) {
    // Keep the original startup error visible while recording a cleanup
    // failure for diagnostics. GetIt has already removed any registrations it
    // could dispose before reporting the failure.
    await _recordCrashSafely(
      'Bootstrap locator cleanup failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _recordCrashSafely(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) async {
  try {
    await LoggingService.recordCrash(
      message,
      error: error,
      stackTrace: stackTrace,
    );
  } on Object catch (recordingError) {
    debugPrint('Crash recording failed: ${recordingError.runtimeType}');
  }
}

class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _BootstrapFailureScreen(error: error, onRetry: onRetry),
    );
  }
}

class _BootstrapFailureScreen extends StatelessWidget {
  const _BootstrapFailureScreen({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = LoggingService.redact(error.toString());
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.bootstrapFailureTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(l10n.bootstrapFailureDescription),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(l10n.bootstrapRetry),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.bootstrapDiagnosticsTitle),
                      content: SelectableText(details),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.done),
                        ),
                      ],
                    ),
                  ),
                  child: Text(l10n.bootstrapDiagnostics),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// coverage:ignore-start
Future<void> _requestAndroidNotificationPermissionIfNeeded() async {
  await requestAndroidNotificationPermissionIfNeeded(
    sdkIntProvider: () async =>
        (await DeviceInfoPlugin().androidInfo).version.sdkInt,
    permissionStatusProvider: () async =>
        FileDownloader().permissions.status(PermissionType.notifications),
    permissionRequest: () async =>
        FileDownloader().permissions.request(PermissionType.notifications),
  );
}
// coverage:ignore-end

@visibleForTesting
Future<void> requestAndroidNotificationPermissionIfNeeded({
  Future<int> Function()? sdkIntProvider,
  Future<PermissionStatus> Function()? permissionStatusProvider,
  Future<PermissionStatus> Function()? permissionRequest,
  Future<SharedPreferences> Function()? sharedPreferencesProvider,
}) async {
  try {
    final resolvedSdkIntProvider =
        sdkIntProvider ??
        // coverage:ignore-start
        () async => (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    // coverage:ignore-end
    if (await resolvedSdkIntProvider() < 33) {
      return;
    }

    final prefs =
        await (sharedPreferencesProvider ?? SharedPreferences.getInstance)();
    final status =
        await (permissionStatusProvider ??
            // coverage:ignore-start
            () async => FileDownloader().permissions.status(
              PermissionType.notifications,
            )
        // coverage:ignore-end
        )();

    if (status == PermissionStatus.granted) {
      return;
    }

    if (prefs.getBool(notificationPermissionRequestAttemptedKey) ?? false) {
      return;
    }

    await prefs.setBool(notificationPermissionRequestAttemptedKey, true);

    if (status != PermissionStatus.undetermined) {
      return;
    }

    await (permissionRequest ??
        // coverage:ignore-start
        () async =>
            FileDownloader().permissions.request(PermissionType.notifications)
    // coverage:ignore-end
    )();
  } on Object catch (error) {
    // Permission failures are expected on unsupported/restricted devices.
    // Keep diagnostics type-only so paths and platform details never enter
    // console logs.
    debugPrint('Notification permission request failed: ${error.runtimeType}');
  }
}
