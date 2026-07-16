import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_usage/disk_usage.dart';
import 'package:flutter/foundation.dart';
import 'package:system_info2/system_info2.dart';

/// Device capabilities for model selection
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.totalRamMB,
    required this.availableStorageMB,
    required this.hasGpu,
    required this.platform,
  });

  final int totalRamMB;
  final int availableStorageMB;
  final bool hasGpu;
  final String platform; // web, android, ios, linux, macos, windows

  @override
  String toString() {
    return 'DeviceCapabilities('
        'RAM: ${totalRamMB}MB, '
        'Storage: ${availableStorageMB}MB, '
        'GPU: $hasGpu, '
        'Platform: $platform)';
  }
}

/// Service to detect device capabilities.
///
/// Uses a composite approach for best reliability:
/// - **Memory**: `system_info2` (FFI-based, high performance)
/// - **Storage**: `disk_usage` (proper platform-specific implementations)
/// - **Metadata**: `device_info_plus` (model, OS info)
///
/// See `docs/resource_monitoring.md` for architectural details.
class DeviceCapabilityService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Minimum thresholds for fallback validation
  static const int _minReasonableRamMB = 512;
  static const int _minReasonableStorageMB = 100;

  // Platform-specific default storage values (fallbacks)
  static const int _mobileDefaultStorageMB = 4096;
  static const int _desktopDefaultStorageMB = 10240;
  static const int _webDefaultStorageMB = 2048;

  Future<DeviceCapabilities> getCapabilities() async {
    try {
      if (kIsWeb) {
        return _getWebCapabilities();
      } else if (Platform.isAndroid) {
        return _getAndroidCapabilities();
      } else if (Platform.isIOS) {
        return _getIosCapabilities();
      } else if (Platform.isLinux) {
        return _getLinuxCapabilities();
      } else if (Platform.isMacOS) {
        return _getMacOsCapabilities();
      } else if (Platform.isWindows) {
        return _getWindowsCapabilities();
      }
    } on Exception catch (e) {
      log('Error detecting device capabilities: $e');
    }

    // Fallback to conservative defaults
    return const DeviceCapabilities(
      totalRamMB: 2048,
      availableStorageMB: 1024,
      hasGpu: false,
      platform: 'unknown',
    );
  }

  Future<DeviceCapabilities> _getWebCapabilities() async {
    // Web: Use conservative defaults since native APIs unavailable
    // deviceMemory on Web is deliberately inaccurate (rounded to powers of 2)
    log('Web platform detected, using conservative defaults');
    return const DeviceCapabilities(
      totalRamMB: 2048,
      availableStorageMB: _webDefaultStorageMB,
      hasGpu: false,
      platform: 'web',
    );
  }

  Future<DeviceCapabilities> _getAndroidCapabilities() async {
    final androidInfo = await _deviceInfo.androidInfo;
    log('Android device: ${androidInfo.model}');

    final ramMB = _detectRam(fallback: 2048);
    final storageMB = await _detectStorage(fallback: _mobileDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: true,
      platform: 'android',
    );
  }

  Future<DeviceCapabilities> _getIosCapabilities() async {
    final iosInfo = await _deviceInfo.iosInfo;
    log('iOS device: ${iosInfo.model}');

    // iOS WARNING: Do not use getFreePhysicalMemory() on iOS.
    // iOS uses Compressed Memory - "Free RAM" is often near zero.
    // Only use getTotalPhysicalMemory for device tier categorization.
    final ramMB = _detectRam(fallback: 2048);
    final storageMB = await _detectStorage(fallback: _mobileDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: true,
      platform: 'ios',
    );
  }

  Future<DeviceCapabilities> _getLinuxCapabilities() async {
    final linuxInfo = await _deviceInfo.linuxInfo;
    log('Linux device: ${linuxInfo.prettyName}');

    final ramMB = _detectRam(fallback: 4096);
    final storageMB = await _detectStorage(fallback: _desktopDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: true,
      platform: 'linux',
    );
  }

  Future<DeviceCapabilities> _getMacOsCapabilities() async {
    final macInfo = await _deviceInfo.macOsInfo;
    log('macOS device: ${macInfo.model}');

    final ramMB = _detectRam(fallback: 4096);
    final storageMB = await _detectStorage(fallback: _desktopDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: true,
      platform: 'macos',
    );
  }

  Future<DeviceCapabilities> _getWindowsCapabilities() async {
    final windowsInfo = await _deviceInfo.windowsInfo;
    log('Windows device: ${windowsInfo.computerName}');

    final ramMB = _detectRam(fallback: 4096);
    final storageMB = await _detectStorage(fallback: _desktopDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: true,
      platform: 'windows',
    );
  }

  /// Detects total RAM using system_info2 (FFI-based).
  ///
  /// Returns [fallback] if detection fails or returns unreasonable values.
  int _detectRam({required int fallback}) {
    try {
      // SysInfo.getTotalPhysicalMemory() is synchronous
      final totalMemory = SysInfo.getTotalPhysicalMemory();
      if (totalMemory > 0) {
        final calculatedRam = totalMemory ~/ (1024 * 1024);
        if (calculatedRam >= _minReasonableRamMB) {
          return calculatedRam;
        } else {
          log('Calculated RAM too small ($calculatedRam MB), using fallback');
        }
      }
    } on Object catch (e) {
      log('Error detecting RAM: $e');
    }
    return fallback;
  }

  /// Detects free storage using disk_usage package.
  ///
  /// Returns [fallback] if detection fails or returns unreasonable values.
  /// Note: On Android 10+, may fail for paths outside app sandbox.
  Future<int> _detectStorage({required int fallback}) async {
    try {
      // DiskUsage.freeSpace() returns available disk space in bytes
      final freeStorage = await DiskUsage.freeSpace();
      if (freeStorage != null && freeStorage > 0) {
        final calculatedStorage = freeStorage ~/ (1024 * 1024);
        if (calculatedStorage >= _minReasonableStorageMB) {
          return calculatedStorage;
        } else {
          log(
            'Calculated storage too small ($calculatedStorage MB), '
            'using fallback',
          );
        }
      }
    } on Object catch (e) {
      log('Error detecting storage: $e');
    }
    return fallback;
  }
}
