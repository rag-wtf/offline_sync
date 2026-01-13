import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';

// Conditional imports for SQLite initialization
import 'package:offline_sync/bootstrap_mobile.dart'
    if (dart.library.html) 'package:offline_sync/bootstrap_web.dart'
    as platform;

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterGemma.initialize();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  // Platform-specific SQLite initialization
  await platform.initializeSqlite();

  await setupLocator();

  runApp(await builder());
}
