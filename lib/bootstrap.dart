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
    // progress notifications are best-effort rather than required for success.
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

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      LoggingService.recordCrash(
        'Unhandled Flutter framework error',
        error: details.exception,
        stackTrace: details.stack,
      ),
    );
  };

  // Platform-specific SQLite initialization
  await (initializeSqliteOverride ?? platform.initializeSqlite)();

  await (setupLocatorOverride ?? setupLocator)();
  (setupDialogUiOverride ?? setupDialogUi)();
  (environmentServiceOverride ?? locator<EnvironmentService>()).flavor = flavor;

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      LoggingService.recordCrash(
        'Unhandled platform error',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    return true;
  };

  try {
    runAppFn(await builder());
  } on Object catch (error, stackTrace) {
    unawaited(
      LoggingService.recordCrash(
        'Unhandled bootstrap error',
        error: error,
        stackTrace: stackTrace,
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
  } on Object catch (error, stackTrace) {
    debugPrint('Notification permission request failed: $error\n$stackTrace');
  }
}
