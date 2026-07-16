class EnvironmentService {
  String flavor = 'development';

  bool get isDevelopment => flavor == 'development';
  bool get isStaging => flavor == 'staging';
  bool get isProduction => flavor == 'production';
}
