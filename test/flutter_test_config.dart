import 'dart:async';

import 'package:google_fonts/google_fonts.dart';
import 'package:offline_sync/app/app_theme.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  AppTheme.useGoogleFonts = false;

  await testMain();
}
