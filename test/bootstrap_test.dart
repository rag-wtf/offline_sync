import 'dart:ui';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/bootstrap.dart';
import 'package:offline_sync/services/environment_service.dart';
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
      expect(prefs.getBool(notificationPermissionRequestAttemptedKey), isTrue);
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
    expect(prefs.getBool(notificationPermissionRequestAttemptedKey), isTrue);
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

  test('returns early on Android versions below 13', () async {
    var statusCalls = 0;
    var requestCalls = 0;

    await requestAndroidNotificationPermissionIfNeeded(
      sdkIntProvider: () async => 32,
      permissionStatusProvider: () async {
        statusCalls += 1;
        return PermissionStatus.undetermined;
      },
      permissionRequest: () async {
        requestCalls += 1;
        return PermissionStatus.granted;
      },
    );

    expect(statusCalls, 0);
    expect(requestCalls, 0);
  });

  test('returns early when permission is already granted', () async {
    var requestCalls = 0;

    await requestAndroidNotificationPermissionIfNeeded(
      sdkIntProvider: () async => 33,
      permissionStatusProvider: () async => PermissionStatus.granted,
      permissionRequest: () async {
        requestCalls += 1;
        return PermissionStatus.granted;
      },
    );

    final prefs = await SharedPreferences.getInstance();
    expect(requestCalls, 0);
    expect(
      prefs.containsKey(notificationPermissionRequestAttemptedKey),
      isFalse,
    );
  });

  testWidgets('bootstrap can use locator-provided environment'
      ' service and default platform lookup', (tester) async {
    await locator.reset();
    final environmentService = EnvironmentService();
    locator.registerSingleton<EnvironmentService>(environmentService);
    addTearDown(locator.reset);

    Widget? renderedApp;

    await bootstrap(
      () async => const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('web bootstrap'),
      ),
      flavor: 'web-test',
      isWebOverride: true,
      flutterGemmaInitialize: () async {},
      initializeSqliteOverride: () async {},
      setupLocatorOverride: () async {},
      runAppOverride: (app) {
        renderedApp = app;
      },
    );

    expect(environmentService.flavor, 'web-test');
    expect(renderedApp, isA<Directionality>());
  });

  testWidgets('bootstrap initializes services, flavor, and runs builder', (
    tester,
  ) async {
    final environmentService = EnvironmentService();
    var flutterGemmaInitialized = 0;
    var sqliteInitialized = 0;
    var setupLocatorCalls = 0;
    var setupDialogUiCalls = 0;
    var builderCalls = 0;
    Widget? renderedApp;

    await bootstrap(
      () async {
        builderCalls += 1;
        return const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('bootstrapped'),
        );
      },
      flavor: 'test',
      isWebOverride: false,
      targetPlatformOverride: TargetPlatform.iOS,
      flutterGemmaInitialize: () async {
        flutterGemmaInitialized += 1;
      },
      initializeSqliteOverride: () async {
        sqliteInitialized += 1;
      },
      setupLocatorOverride: () async {
        setupLocatorCalls += 1;
      },
      setupDialogUiOverride: () {
        setupDialogUiCalls += 1;
      },
      environmentServiceOverride: environmentService,
      runAppOverride: (app) {
        renderedApp = app;
      },
      requestNotificationPermissionOverride: () async {},
      configureDownloaderOverride: () async {},
      configureDownloaderNotificationOverride: () {},
    );

    expect(flutterGemmaInitialized, 1);
    expect(sqliteInitialized, 1);
    expect(setupLocatorCalls, 1);
    expect(setupDialogUiCalls, 1);
    expect(builderCalls, 1);
    expect(environmentService.flavor, 'test');
    expect(renderedApp, isA<Directionality>());
  });

  testWidgets('bootstrap runs Android-specific configuration hooks', (
    tester,
  ) async {
    final previousOnError = FlutterError.onError;
    final previousPresentError = FlutterError.presentError;
    FlutterError.presentError = (_) {};
    addTearDown(() {
      FlutterError.onError = previousOnError;
      FlutterError.presentError = previousPresentError;
    });

    final environmentService = EnvironmentService();
    var configureDownloaderCalls = 0;
    var configureNotificationCalls = 0;
    var requestPermissionCalls = 0;

    await bootstrap(
      () async => throw StateError('builder failed'),
      flavor: 'android',
      isWebOverride: false,
      targetPlatformOverride: TargetPlatform.android,
      flutterGemmaInitialize: () async {},
      initializeSqliteOverride: () async {},
      setupLocatorOverride: () async {},
      environmentServiceOverride: environmentService,
      runAppOverride: (_) {},
      requestNotificationPermissionOverride: () async {
        requestPermissionCalls += 1;
      },
      configureDownloaderOverride: () async {
        configureDownloaderCalls += 1;
      },
      configureDownloaderNotificationOverride: () {
        configureNotificationCalls += 1;
      },
    );

    expect(configureDownloaderCalls, 1);
    expect(configureNotificationCalls, 1);
    expect(requestPermissionCalls, 1);
    expect(environmentService.flavor, 'android');
  });

  testWidgets('bootstrap renders a retryable localized failure app', (
    tester,
  ) async {
    final previousOnError = FlutterError.onError;
    final previousPlatformError = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = previousOnError;
      PlatformDispatcher.instance.onError = previousPlatformError;
    });

    Widget? renderedApp;
    var handlersInstalledBeforeFailure = false;

    await bootstrap(
      () async => const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('unreachable'),
      ),
      flavor: 'production',
      isWebOverride: true,
      flutterGemmaInitialize: () async {
        handlersInstalledBeforeFailure =
            FlutterError.onError != null &&
            PlatformDispatcher.instance.onError != null;
        throw StateError('sqlite unavailable');
      },
      runAppOverride: (app) {
        renderedApp = app;
      },
    );

    FlutterError.onError = previousOnError;
    PlatformDispatcher.instance.onError = previousPlatformError;
    expect(handlersInstalledBeforeFailure, isTrue);
    expect(renderedApp, isNotNull);
    await tester.pumpWidget(renderedApp!);
    expect(find.text('Offline Sync could not start'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Show diagnostics'), findsOneWidget);
  });

  testWidgets(
    'bootstrap resets and disposes locator services before retrying',
    (tester) async {
      final previousOnError = FlutterError.onError;
      final previousPlatformError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousOnError;
        PlatformDispatcher.instance.onError = previousPlatformError;
      });
      await locator.reset();
      addTearDown(locator.reset);

      final environmentService = EnvironmentService();
      var setupLocatorCalls = 0;
      var setupDialogUiCalls = 0;
      var builderCalls = 0;
      var serviceDisposed = false;
      Widget? renderedApp;

      await bootstrap(
        () async {
          builderCalls += 1;
          return const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('retried successfully'),
          );
        },
        flavor: 'production',
        isWebOverride: true,
        flutterGemmaInitialize: () async {},
        initializeSqliteOverride: () async {},
        setupLocatorOverride: () async {
          setupLocatorCalls += 1;
          locator.registerSingleton<EnvironmentService>(
            environmentService,
            dispose: (_) => serviceDisposed = true,
          );
        },
        setupDialogUiOverride: () {
          setupDialogUiCalls += 1;
          if (setupDialogUiCalls == 1) {
            throw StateError('dialog setup failed');
          }
        },
        environmentServiceOverride: environmentService,
        runAppOverride: (app) => renderedApp = app,
      );

      await tester.pumpWidget(renderedApp!);
      expect(find.text('Offline Sync could not start'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      FlutterError.onError = previousOnError;
      PlatformDispatcher.instance.onError = previousPlatformError;

      expect(setupLocatorCalls, 2);
      expect(setupDialogUiCalls, 2);
      expect(serviceDisposed, isTrue);
      expect(builderCalls, 1);
      expect(renderedApp, isA<Directionality>());
    },
  );
}
