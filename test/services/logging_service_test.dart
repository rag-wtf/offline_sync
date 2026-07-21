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

    test('recordCrash persists message, error, and stack trace', () async {
      final trace = StackTrace.fromString('stack line 1\nstack line 2');

      await LoggingService.recordCrash(
        'Unexpected failure',
        error: StateError('bad state'),
        stackTrace: trace,
      );

      final prefs = await SharedPreferences.getInstance();
      final crashLogs = prefs.getStringList('crash_logs');

      expect(crashLogs, hasLength(1));
      expect(crashLogs!.single, contains('Unexpected failure'));
      expect(crashLogs.single, contains('Bad state: bad state'));
      expect(crashLogs.single, contains('stack line 1'));
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
      expect(
        () {
          LoggingService.log('generic', level: Level.warning);
          LoggingService.info('info');
          LoggingService.debug('debug');
          LoggingService.warning('warn');
          LoggingService.error(
            'error',
            error: ArgumentError('bad arg'),
            stackTrace: StackTrace.empty,
          );
        },
        returnsNormally,
      );
    });
  });
}
