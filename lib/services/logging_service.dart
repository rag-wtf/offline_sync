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
    _logger.log(
      level,
      _safeMessage(message),
      error: _safeError(error),
    );
  }

  static void info(String message, {String? name}) =>
      _logger.i(_safeMessage(message));

  static void debug(String message, {String? name}) =>
      _logger.d(_safeMessage(message));

  static void warning(String message, {String? name}) =>
      _logger.w(_safeMessage(message));

  static void error(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) => _logger.e(
    _safeMessage(message),
    error: _safeError(error),
  );

  static Future<void> recordCrash(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    _logger.e(_safeMessage(message), error: _safeError(error));

    if (kIsWeb) {
      // coverage:ignore-line
      // coverage:ignore-start
      return _persistCrashRecord(message, error: error, stackTrace: stackTrace);
      // coverage:ignore-end
    }

    try {
      await _persistCrashRecord(message, error: error, stackTrace: stackTrace);
      // coverage:ignore-start
    } on Object catch (writeError) {
      _logger.w(
        'Failed to persist crash log',
        error: writeError.runtimeType.toString(),
      );
    }
    // coverage:ignore-end
  }

  static Future<void> _persistCrashRecord(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final crashLogs = prefs.getStringList(_crashLogKey) ?? <String>[];
    final buffer = StringBuffer()
      ..writeln(
        '[${DateTime.now().toIso8601String()}] ${_safeMessage(message)}',
      )
      ..writeln('errorType: ${error?.runtimeType ?? 'none'}');
    crashLogs.add(buffer.toString());
    if (crashLogs.length > 50) {
      crashLogs.removeRange(0, crashLogs.length - 50);
    }
    await prefs.setStringList(_crashLogKey, crashLogs);
  }

  static Future<List<String>> getCrashLogs() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_crashLogKey) ?? <String>[])
        .map(_sanitizePersistedRecord)
        .toList();
  }

  static Future<void> clearCrashLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_crashLogKey);
  }

  static Object? _safeError(Object? error) => error?.runtimeType.toString();

  static String _safeMessage(String message) {
    if (RegExp(
      r'\b(query|content|document|prompt|file(?:path|name)?)\b|'
      r'(?:[A-Za-z]:[\\/]|\\\\|/(?:Users|home)[\\/])',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'Crash recorded';
    }
    return redact(message);
  }

  /// Removes credentials, URLs, and local paths before diagnostics leave the
  /// process or are persisted. This is also used for legacy records.
  static String redact(String value) {
    var safe = value.replaceAll(
      RegExp(
        r'\b(?:authorization|token|api[-_ ]?key|password|secret)\s*[:=]\s*(?:bearer\s+)?[^\s,;)]*|\bbearer\s+[^\s,;)]*',
        caseSensitive: false,
      ),
      '[redacted-credential]',
    );
    safe = safe.replaceAll(
      RegExp(r'\b(?:hf|sk)-[A-Za-z0-9_-]{8,}\b', caseSensitive: false),
      '[redacted-token]',
    );
    safe = safe.replaceAll(
      RegExp(r'https?://[^\s)]+', caseSensitive: false),
      '[redacted-url]',
    );
    return safe.replaceAll(
      RegExp(
        r'(?:[A-Z]:[\\/]|\\\\|/(?:Users|home|private|tmp|var)/)[^\s\n,;)]*',
        caseSensitive: false,
      ),
      '[redacted-path]',
    );
  }

  static String _sanitizePersistedRecord(String record) {
    final firstLine = record.split('\n').first;
    final separator = firstLine.indexOf('] ');
    if (separator == -1) return 'Crash recorded';
    final timestamp = firstLine.substring(0, separator + 1);
    final message = firstLine.substring(separator + 2);
    return '$timestamp ${_safeMessage(message)}\nerrorType: LegacyCrashRecord';
  }
}
