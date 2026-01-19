import 'package:logger/logger.dart';

/// Unified logging service for the application
class LoggingService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

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
}
