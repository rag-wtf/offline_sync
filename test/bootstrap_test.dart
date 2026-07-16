import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'requests notification permission once on Android 13+ when undetermined',
    () async {
      var requestCount = 0;

      await requestAndroidNotificationPermissionIfNeeded(
        sdkIntProvider: () async => 33,
        permissionStatusProvider: () async => PermissionStatus.undetermined,
        permissionRequest: () async {
          requestCount += 1;
          return PermissionStatus.denied;
        },
      );

      final prefs = await SharedPreferences.getInstance();
      expect(requestCount, 1);
      expect(
        prefs.getBool(notificationPermissionRequestAttemptedKey),
        isTrue,
      );
    },
  );

  test(
    'does not re-request notification permission after a denied attempt',
    () async {
      SharedPreferences.setMockInitialValues({
        notificationPermissionRequestAttemptedKey: true,
      });
      var requestCount = 0;

      await requestAndroidNotificationPermissionIfNeeded(
        sdkIntProvider: () async => 33,
        permissionStatusProvider: () async => PermissionStatus.denied,
        permissionRequest: () async {
          requestCount += 1;
          return PermissionStatus.denied;
        },
      );

      expect(requestCount, 0);
    },
  );

  test('marks denied status as attempted without requesting again', () async {
    var requestCount = 0;

    await requestAndroidNotificationPermissionIfNeeded(
      sdkIntProvider: () async => 33,
      permissionStatusProvider: () async => PermissionStatus.denied,
      permissionRequest: () async {
        requestCount += 1;
        return PermissionStatus.denied;
      },
    );

    final prefs = await SharedPreferences.getInstance();
    expect(requestCount, 0);
    expect(
      prefs.getBool(notificationPermissionRequestAttemptedKey),
      isTrue,
    );
  });

  test('swallows notification permission failures', () async {
    await expectLater(
      requestAndroidNotificationPermissionIfNeeded(
        sdkIntProvider: () async => 33,
        permissionStatusProvider: () async {
          throw StateError('status failed');
        },
      ),
      completes,
    );
  });
}
