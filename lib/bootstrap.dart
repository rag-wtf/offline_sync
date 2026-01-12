import 'dart:async';
import 'dart:developer';
import 'dart:ffi';

import 'package:flutter/widgets.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:sqlite3/open.dart';

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  open.overrideFor(OperatingSystem.linux, () {
    return DynamicLibrary.open('libsqlite3.so.0');
  });

  await setupLocator();

  runApp(await builder());
}
