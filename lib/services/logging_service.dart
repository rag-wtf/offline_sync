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
  }) => _logger.log(
    level,
    redact(message),
    error: _safeError(error),
    stackTrace: _safeStackTrace(stackTrace),
  );

  static void info(String message, {String? name}) =>
      _logger.i(redact(message));

  static void debug(String message, {String? name}) =>
      _logger.d(redact(message));

  static void warning(String message, {String? name}) =>
      _logger.w(redact(message));

  static void error(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) => _logger.e(
    redact(message),
    error: _safeError(error),
    stackTrace: _safeStackTrace(stackTrace),
  );

  static Future<void> recordCrash(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final safeMessage = redact(message);
    final safeError = _safeError(error);
    final errorType = error?.runtimeType.toString();
    final safeStackTrace = _safeStackTrace(stackTrace);
    _logger.e(safeMessage, error: safeError, stackTrace: safeStackTrace);

    if (kIsWeb) {
      // coverage:ignore-line
      // coverage:ignore-start
      return _persistCrashRecord(
        safeMessage,
        errorType: errorType,
        stackTrace: safeStackTrace,
      );
      // coverage:ignore-end
    }

    try {
      await _persistCrashRecord(
        safeMessage,
        errorType: errorType,
        stackTrace: safeStackTrace,
      );
      // coverage:ignore-start
    } on Object catch (writeError, writeStackTrace) {
      _logger.w(
        'Failed to persist crash log',
        error: writeError,
        stackTrace: writeStackTrace,
      );
    }
    // coverage:ignore-end
  }

  static Future<void> _persistCrashRecord(
    String message, {
    String? errorType,
    StackTrace? stackTrace,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final crashLogs = prefs.getStringList(_crashLogKey) ?? <String>[];
    final buffer = StringBuffer()
      ..writeln('[${DateTime.now().toIso8601String()}] $message')
      ..writeln('errorType: ${errorType ?? 'none'}');
    if (stackTrace != null) {
      buffer.writeln(redact(stackTrace.toString()));
    }
    crashLogs.add(buffer.toString());
    if (crashLogs.length > 50) {
      crashLogs.removeRange(0, crashLogs.length - 50);
    }
    await prefs.setStringList(_crashLogKey, crashLogs);
  }

  static Future<List<String>> getCrashLogs() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_crashLogKey) ?? <String>[])
        .map(redact)
        .toList(growable: false);
  }

  static Future<void> clearCrashLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_crashLogKey);
  }

  /// Redacts values that may identify a user, local file, or credential.
  /// This is deliberately public so platform/UI diagnostics can share the
  /// same privacy boundary without depending on logger internals.
  static String redact(String value) {
    final safe = value
        .replaceAll(
          RegExp(r'\b(?:hf|sk)-[A-Za-z0-9_-]{8,}\b', caseSensitive: false),
          '[redacted-token]',
        )
        .replaceAll(
          RegExp(
            r'\b(?:authorization|bearer|token|api[-_ ]?key|password|secret)\s*[:=]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          '[redacted-credential]',
        )
        .replaceAll(
          RegExp(r'\bhttps?://[^\s)]+', caseSensitive: false),
          '[redacted-url]',
        );
    // Keep the first redaction pass separate so path replacement also applies
    // to messages that contained a URL or credential.
    return safe.replaceAll(
      RegExp(
        r'(?:[A-Z]:[\\/]|\\\\|/(?:Users|home|private|tmp|var)/)[^\s\n,;)]*',
        caseSensitive: false,
      ),
      '[redacted-path]',
    );
  }

  static Object? _safeError(Object? error) {
    if (error == null) return null;
    return error.runtimeType.toString();
  }

  static StackTrace? _safeStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    return StackTrace.fromString(redact(stackTrace.toString()));
  }
}
