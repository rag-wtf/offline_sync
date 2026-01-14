import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/environment_service.dart';

void main() {
  group('EnvironmentServiceTest -', () {
    late EnvironmentService service;

    setUp(() {
      service = EnvironmentService();
    });

    test('should return true for isDevelopment when flavor is development', () {
      service.flavor = 'development';
      expect(service.isDevelopment, isTrue);
      expect(service.isStaging, isFalse);
      expect(service.isProduction, isFalse);
    });

    test('should return true for isStaging when flavor is staging', () {
      service.flavor = 'staging';
      expect(service.isDevelopment, isFalse);
      expect(service.isStaging, isTrue);
      expect(service.isProduction, isFalse);
    });

    test('should return true for isProduction when flavor is production', () {
      service.flavor = 'production';
      expect(service.isDevelopment, isFalse);
      expect(service.isStaging, isFalse);
      expect(service.isProduction, isTrue);
    });
  });
}
