import 'package:offline_sync/services/logging_service.dart';

class EnvironmentService {
  String _flavor = 'development';

  String get flavor => _flavor;

  set flavor(String value) {
    _flavor = value;
    LoggingService.configureFlavor(value);
  }

  bool get isDevelopment => flavor == 'development';
  bool get isStaging => flavor == 'staging';
  bool get isProduction => flavor == 'production';
}
