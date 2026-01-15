import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AuthTokenServiceTest -', () {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final secureStorageValues = <String, String>{};

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      secureStorageValues.clear();

      // Mock FlutterSecureStorage via MethodChannel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            final args = methodCall.arguments as Map<dynamic, dynamic>? ?? {};
            final key = args['key'] as String?;
            final value = args['value'] as String?;

            switch (methodCall.method) {
              case 'read':
                return secureStorageValues[key];
              case 'write':
                if (key != null && value != null) {
                  secureStorageValues[key] = value;
                }
                return null;
              case 'delete':
                if (key != null) {
                  secureStorageValues.remove(key);
                }
                return null;
              case 'deleteAll':
                secureStorageValues.clear();
                return null;
              case 'containsKey':
                return secureStorageValues.containsKey(key);
              default:
                return null;
            }
          });

      SharedPreferences.setMockInitialValues({});
    });

    test('saveToken saves to secure storage', () async {
      await AuthTokenService.saveToken('test_token');
      expect(secureStorageValues['auth_token'], 'test_token');
    });

    test('loadToken retrieves from secure storage', () async {
      secureStorageValues['auth_token'] = 'stored_token';
      final token = await AuthTokenService.loadToken();
      expect(token, 'stored_token');
    });

    test(
      'loadToken migrates from SharedPreferences if secure storage is empty',
      () async {
        // Setup SharedPreferences with legacy token
        SharedPreferences.setMockInitialValues({'auth_token': 'legacy_token'});

        // Ensure secure storage is empty
        expect(secureStorageValues['auth_token'], isNull);

        final token = await AuthTokenService.loadToken();
        expect(token, 'legacy_token');

        // Verify migration
        expect(secureStorageValues['auth_token'], 'legacy_token');

        // Verify removal from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('auth_token'), isFalse);
      },
    );

    test(
      'clearToken removes from secure storage and SharedPreferences',
      () async {
        secureStorageValues['auth_token'] = 'token_to_delete';
        SharedPreferences.setMockInitialValues({
          'auth_token': 'legacy_token_to_delete',
        });

        await AuthTokenService.clearToken();

        expect(secureStorageValues['auth_token'], isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('auth_token'), isFalse);
      },
    );

    test('hasToken returns true if token exists', () async {
      secureStorageValues['auth_token'] = 'existing_token';
      expect(await AuthTokenService.hasToken(), isTrue);
    });

    test('hasToken returns false if token does not exist', () async {
      expect(await AuthTokenService.hasToken(), isFalse);
    });
  });
}
