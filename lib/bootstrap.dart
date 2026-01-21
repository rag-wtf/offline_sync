import 'dart:async';
import 'dart:developer';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';

// Conditional imports for SQLite initialization
import 'package:offline_sync/bootstrap_mobile.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart'
    as platform;

import 'package:offline_sync/services/environment_service.dart';

Future<void> bootstrap(
  FutureOr<Widget> Function() builder, {
  required String flavor,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure FileDownloader for foreground mode on Android to prevent
  // WorkManager from cancelling downloads on network state changes. This must
  // be called before FlutterGemma.initialize() which uses the downloader.
  // IMPORTANT: Foreground mode requires a notification to be configured!
  if (defaultTargetPlatform == TargetPlatform.android) {
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
  }

  await FlutterGemma.initialize();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  // Platform-specific SQLite initialization
  await platform.initializeSqlite();

  await setupLocator();
  locator<EnvironmentService>().flavor = flavor;

  runApp(await builder());
}
