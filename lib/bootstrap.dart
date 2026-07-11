import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';

// Conditional imports for SQLite initialization
import 'package:offline_sync/bootstrap_mobile.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart'
    as platform;

import 'package:offline_sync/services/environment_service.dart';
import 'package:offline_sync/services/logging_service.dart';

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
    await _requestAndroidNotificationPermissionIfNeeded();
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
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  if (androidInfo.version.sdkInt < 33) {
    return;
  }

  final status = await FileDownloader().permissions.status(
    PermissionType.notifications,
  );
  if (status == PermissionStatus.undetermined ||
      status == PermissionStatus.denied) {
    await FileDownloader().permissions.request(PermissionType.notifications);
  }
}
