import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/device_capability_service.dart';

void main() {
  group('DeviceCapabilityService', () {
    test('returns conservative web defaults', () async {
      final service = DeviceCapabilityService(
        isWebOverride: true,
      );

      expect(
        await service.getCapabilities(),
        const TypeMatcher<DeviceCapabilities>()
            .having((c) => c.totalRamMB, 'totalRamMB', 2048)
            .having(
              (c) => c.availableStorageMB,
              'availableStorageMB',
              2048,
            )
            .having((c) => c.hasGpu, 'hasGpu', false)
            .having((c) => c.platform, 'platform', 'web'),
      );
    });

    test('uses Android detectors and metadata when available', () async {
      final service = DeviceCapabilityService(
        isAndroidOverride: true,
        androidModelProvider: () async => 'Pixel Test',
        totalRamProvider: () => 8 * 1024 * 1024 * 1024,
        freeStorageProvider: () async => 6 * 1024 * 1024 * 1024,
      );

      expect(
        await service.getCapabilities(),
        const TypeMatcher<DeviceCapabilities>()
            .having((c) => c.totalRamMB, 'totalRamMB', 8192)
            .having(
              (c) => c.availableStorageMB,
              'availableStorageMB',
              6144,
            )
            .having((c) => c.hasGpu, 'hasGpu', true)
            .having((c) => c.platform, 'platform', 'android'),
      );
    });

    test('falls back when detector values are unreasonable', () async {
      final service = DeviceCapabilityService(
        isAndroidOverride: true,
        androidModelProvider: () async => 'Tiny Device',
        totalRamProvider: () => 1000,
        freeStorageProvider: () async => 10,
      );

      expect(
        await service.getCapabilities(),
        const TypeMatcher<DeviceCapabilities>()
            .having((c) => c.totalRamMB, 'totalRamMB', 2048)
            .having(
              (c) => c.availableStorageMB,
              'availableStorageMB',
              4096,
            ),
      );
    });

    test('returns unknown fallback when platform branch throws', () async {
      final service = DeviceCapabilityService(
        isLinuxOverride: true,
        linuxPrettyNameProvider: () async => throw Exception('boom'),
      );

      expect(
        await service.getCapabilities(),
        const TypeMatcher<DeviceCapabilities>()
            .having((c) => c.totalRamMB, 'totalRamMB', 2048)
            .having((c) => c.availableStorageMB, 'availableStorageMB', 1024)
            .having((c) => c.hasGpu, 'hasGpu', false)
            .having((c) => c.platform, 'platform', 'unknown'),
      );
    });

    test('uses iOS, Linux, macOS, and Windows'
        ' branches with fallback handling', () async {
      final iosService = DeviceCapabilityService(
        isAndroidOverride: false,
        isIosOverride: true,
        isLinuxOverride: false,
        isMacOsOverride: false,
        isWindowsOverride: false,
        iosModelProvider: () async => 'iPhone Test',
        totalRamProvider: () => 4 * 1024 * 1024 * 1024,
        freeStorageProvider: () async => 2 * 1024 * 1024 * 1024,
      );
      final linuxService = DeviceCapabilityService(
        isAndroidOverride: false,
        isIosOverride: false,
        isLinuxOverride: true,
        isMacOsOverride: false,
        isWindowsOverride: false,
        linuxPrettyNameProvider: () async => 'Ubuntu Test',
        totalRamProvider: () => throw StateError('ram'),
        freeStorageProvider: () async => null,
      );
      final macService = DeviceCapabilityService(
        isAndroidOverride: false,
        isIosOverride: false,
        isLinuxOverride: false,
        isMacOsOverride: true,
        isWindowsOverride: false,
        macOsModelProvider: () async => 'Mac Test',
        totalRamProvider: () => 16 * 1024 * 1024 * 1024,
        freeStorageProvider: () async => 20 * 1024 * 1024 * 1024,
      );
      final windowsService = DeviceCapabilityService(
        isAndroidOverride: false,
        isIosOverride: false,
        isLinuxOverride: false,
        isMacOsOverride: false,
        isWindowsOverride: true,
        windowsComputerNameProvider: () async => 'PC Test',
        totalRamProvider: () => 8 * 1024 * 1024 * 1024,
        freeStorageProvider: () async => throw StateError('disk'),
      );

      expect((await iosService.getCapabilities()).platform, 'ios');
      expect((await linuxService.getCapabilities()).platform, 'linux');
      expect((await linuxService.getCapabilities()).totalRamMB, 4096);
      expect((await linuxService.getCapabilities()).availableStorageMB, 10240);
      expect((await macService.getCapabilities()).platform, 'macos');
      expect((await windowsService.getCapabilities()).platform, 'windows');
      expect(
        (await windowsService.getCapabilities()).availableStorageMB,
        10240,
      );
    });
  });

  group('DeviceCapabilities', () {
    test('toString includes all fields', () {
      const capabilities = DeviceCapabilities(
        totalRamMB: 2048,
        availableStorageMB: 4096,
        hasGpu: true,
        platform: 'android',
      );

      final result = capabilities.toString();

      expect(result, contains('RAM: 2048MB'));
      expect(result, contains('Storage: 4096MB'));
      expect(result, contains('GPU: true'));
      expect(result, contains('Platform: android'));
    });
  });
}
