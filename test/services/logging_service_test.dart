import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:offline_sync/services/logging_service.dart';

void main() {
  group('LoggingService', () {
    test('defaults to debug level in non-release builds', () {
      expect(LoggingService.minimumLevel, Level.debug);
    });
  });
}
