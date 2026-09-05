import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LoggingService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to debug level in non-release builds', () {
      expect(LoggingService.minimumLevel, Level.debug);
    });

    test('crash records omit error and stack data', () async {
      await LoggingService.recordCrash(
        'Unexpected failure',
        error: StateError('document secret content and query text'),
        stackTrace: StackTrace.fromString('query: document secret content'),
      );

      final prefs = await SharedPreferences.getInstance();
      final crashLogs = prefs.getStringList('crash_logs');

      expect(crashLogs, hasLength(1));
      expect(crashLogs!.single, contains('Unexpected failure'));
      expect(crashLogs.single, isNot(contains('document secret content')));
      expect(crashLogs.single, isNot(contains('query text')));
      expect(crashLogs.single, isNot(contains('stack line 1')));
    });

    test('crash records redact private paths from messages', () async {
      await LoggingService.recordCrash(
        r'Failed to open C:\Users\alice\private\notes.txt',
      );

      final logs = await LoggingService.getCrashLogs();

      expect(logs.single, isNot(contains(r'C:\Users\alice\private\notes.txt')));
      expect(logs.single, contains('Crash recorded'));
    });

    test('crash records redact credentials, URLs, and paths', () async {
      await LoggingService.recordCrash(
        'request failed authorization=Bearer secret-token '
        'https://example.com/private?token=secret C:\\Users\\alice\\notes.txt',
      );

      final prefs = await SharedPreferences.getInstance();
      final record = prefs.getStringList('crash_logs')!.single;

      expect(record, isNot(contains('secret-token')));
      expect(record, isNot(contains('https://example.com')));
      expect(record, isNot(contains(r'C:\Users\alice\notes.txt')));
    });

    test('recordCrash keeps only the newest fifty crash logs', () async {
      SharedPreferences.setMockInitialValues({
        'crash_logs': List.generate(50, (index) => 'existing-$index'),
      });

      await LoggingService.recordCrash('new crash');

      final prefs = await SharedPreferences.getInstance();
      final crashLogs = prefs.getStringList('crash_logs');

      expect(crashLogs, hasLength(50));
      expect(crashLogs!.first, 'existing-1');
      expect(crashLogs.last, contains('new crash'));
    });

    test('wrapper log methods can be invoked without throwing', () {
      expect(() {
        LoggingService.log('generic', level: Level.warning);
        LoggingService.info('info');
        LoggingService.debug('debug');
        LoggingService.warning('warn');
        LoggingService.error(
          'error',
          error: ArgumentError('bad arg'),
          stackTrace: StackTrace.empty,
        );
      }, returnsNormally);
    });
  });
}
