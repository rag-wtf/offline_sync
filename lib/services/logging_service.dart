import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified logging service for the application
class LoggingService {
  static const Level minimumLevel = kReleaseMode ? Level.warning : Level.debug;
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: minimumLevel,
  );
  static const _crashLogKey = 'crash_logs';

  static void log(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
    Level level = Level.info,
  }) {
    _logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {String? name}) => _logger.i(message);

  static void debug(String message, {String? name}) => _logger.d(message);

  static void warning(String message, {String? name}) => _logger.w(message);

  static void error(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) => _logger.e(message, error: error, stackTrace: stackTrace);

  static Future<void> recordCrash(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    _logger.e(message, error: error, stackTrace: stackTrace);

    if (kIsWeb) {
      return _persistCrashRecord(message, error: error, stackTrace: stackTrace);
    }

    try {
      await _persistCrashRecord(message, error: error, stackTrace: stackTrace);
    } on Object catch (writeError, writeStackTrace) {
      _logger.w(
        'Failed to persist crash log',
        error: writeError,
        stackTrace: writeStackTrace,
      );
    }
  }

  static Future<void> _persistCrashRecord(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final crashLogs = prefs.getStringList(_crashLogKey) ?? <String>[];
    final buffer = StringBuffer()
      ..writeln('[${DateTime.now().toIso8601String()}] $message')
      ..writeln('error: ${error ?? 'none'}');
    if (stackTrace != null) {
      buffer.writeln(stackTrace);
    }
    crashLogs.add(buffer.toString());
    if (crashLogs.length > 50) {
      crashLogs.removeRange(0, crashLogs.length - 50);
    }
    await prefs.setStringList(_crashLogKey, crashLogs);
  }
}
