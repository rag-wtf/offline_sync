import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/bootstrap_mobile.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart'
    as platform;
import 'package:offline_sync/services/environment_service.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const notificationPermissionRequestAttemptedKey =
    'notification_permission_request_attempted';

Future<void> bootstrap(
  FutureOr<Widget> Function() builder, {
  required String flavor,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure FileDownloader for foreground mode on Android to prevent
  // WorkManager from cancelling downloads on network state changes. This must
  // be called before FlutterGemma.initialize() which uses the downloader.
  // IMPORTANT: Foreground mode requires a notification to be configured!
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Configure foreground mode for files >= 0 MB (all files)
    await FileDownloader().configure(
      androidConfig: (Config.runInForegroundIfFileLargerThan, 0),
    );

    // Configure notification for the 'smart_downloads' group used by
    // SmartDownloader. Without a 'running' notification, foreground mode is
    // ignored!
    FileDownloader().configureNotificationForGroup(
      'smart_downloads',
      running: const TaskNotification(
        'Downloading Model',
        '{displayName} - {progress}%',
      ),
      progressBar: true,
    );

    // Android 13+ requires a runtime grant for notification visibility.
    // Downloads still run in the foreground if the permission is denied, so
    // progress notifications are best-effort rather than required for success.
    unawaited(_requestAndroidNotificationPermissionIfNeeded());
  }

  await FlutterGemma.initialize();

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
  await platform.initializeSqlite();

  await setupLocator();
  locator<EnvironmentService>().flavor = flavor;

  await runZonedGuarded(
    () async {
      runApp(await builder());
    },
    (error, stackTrace) {
      unawaited(
        LoggingService.recordCrash(
          'Unhandled zone error',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    },
  );
}

Future<void> _requestAndroidNotificationPermissionIfNeeded() async {
  await requestAndroidNotificationPermissionIfNeeded(
    sdkIntProvider: () async =>
        (await DeviceInfoPlugin().androidInfo).version.sdkInt,
    permissionStatusProvider: () async => FileDownloader().permissions.status(
      PermissionType.notifications,
    ),
    permissionRequest: () async => FileDownloader().permissions.request(
      PermissionType.notifications,
    ),
  );
}

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
        () async => (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (await resolvedSdkIntProvider() < 33) {
      return;
    }

    final prefs =
        await (sharedPreferencesProvider ?? SharedPreferences.getInstance)();
    final status =
        await (permissionStatusProvider ??
            () async => FileDownloader().permissions.status(
              PermissionType.notifications,
            ))();

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
        () async => FileDownloader().permissions.request(
          PermissionType.notifications,
        ))();
  } on Object catch (error, stackTrace) {
    debugPrint(
      'Notification permission request failed: $error\n$stackTrace',
    );
  }
}
