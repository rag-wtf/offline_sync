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
  DeviceCapabilityService({
    DeviceInfoPlugin? deviceInfo,
    this._isWebOverride,
    this._isAndroidOverride,
    this._isIosOverride,
    this._isLinuxOverride,
    this._isMacOsOverride,
    this._isWindowsOverride,
    this._androidModelProvider,
    this._iosModelProvider,
    this._linuxPrettyNameProvider,
    this._macOsModelProvider,
    this._windowsComputerNameProvider,
    this._totalRamProvider,
    this._freeStorageProvider,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;
  final bool? _isWebOverride;
  final bool? _isAndroidOverride;
  final bool? _isIosOverride;
  final bool? _isLinuxOverride;
  final bool? _isMacOsOverride;
  final bool? _isWindowsOverride;
  final Future<String> Function()? _androidModelProvider;
  final Future<String> Function()? _iosModelProvider;
  final Future<String> Function()? _linuxPrettyNameProvider;
  final Future<String> Function()? _macOsModelProvider;
  final Future<String> Function()? _windowsComputerNameProvider;
  final int Function()? _totalRamProvider;
  final Future<int?> Function()? _freeStorageProvider;
  Future<DeviceCapabilities>? _capabilitiesFuture;

  // Minimum thresholds for fallback validation
  static const int _minReasonableRamMB = 512;
  static const int _minReasonableStorageMB = 100;

  // Platform-specific default storage values (fallbacks)
  static const int _mobileDefaultStorageMB = 4096;
  static const int _desktopDefaultStorageMB = 10240;
  static const int _webDefaultStorageMB = 2048;

  Future<DeviceCapabilities> getCapabilities({bool refresh = false}) {
    if (refresh) _capabilitiesFuture = null;
    return _capabilitiesFuture ??= _detectCapabilities();
  }

  Future<DeviceCapabilities> _detectCapabilities() async {
    try {
      if (_isWebOverride ?? kIsWeb) {
        return await _getWebCapabilities();
      } else if (_isAndroidOverride ?? Platform.isAndroid) {
        return await _getAndroidCapabilities();
      } else if (_isIosOverride ?? Platform.isIOS) {
        return await _getIosCapabilities();
      } else if (_isLinuxOverride ?? Platform.isLinux) {
        return await _getLinuxCapabilities();
      } else if (_isMacOsOverride ?? Platform.isMacOS) {
        return await _getMacOsCapabilities();
      } else if (_isWindowsOverride ?? Platform.isWindows) {
        return await _getWindowsCapabilities();
      }
    } on Object catch (e) {
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
    final model =
        await (_androidModelProvider ??
            () async => (await _deviceInfo.androidInfo).model)();
    log('Android device: $model');

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
    final model =
        await (_iosModelProvider ??
            () async => (await _deviceInfo.iosInfo).model)();
    log('iOS device: $model');

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
    final prettyName =
        await (_linuxPrettyNameProvider ??
            () async => (await _deviceInfo.linuxInfo).prettyName)();
    log('Linux device: $prettyName');

    final ramMB = _detectRam(fallback: 4096);
    final storageMB = await _detectStorage(fallback: _desktopDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: false,
      platform: 'linux',
    );
  }

  Future<DeviceCapabilities> _getMacOsCapabilities() async {
    final model =
        await (_macOsModelProvider ??
            () async => (await _deviceInfo.macOsInfo).model)();
    log('macOS device: $model');

    final ramMB = _detectRam(fallback: 4096);
    final storageMB = await _detectStorage(fallback: _desktopDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: false,
      platform: 'macos',
    );
  }

  Future<DeviceCapabilities> _getWindowsCapabilities() async {
    final computerName =
        await (_windowsComputerNameProvider ??
            () async => (await _deviceInfo.windowsInfo).computerName)();
    log('Windows device: $computerName');

    final ramMB = _detectRam(fallback: 4096);
    final storageMB = await _detectStorage(fallback: _desktopDefaultStorageMB);

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: storageMB,
      hasGpu: false,
      platform: 'windows',
    );
  }

  /// Detects total RAM using system_info2 (FFI-based).
  ///
  /// Returns [fallback] if detection fails or returns unreasonable values.
  int _detectRam({required int fallback}) {
    try {
      // SysInfo.getTotalPhysicalMemory() is synchronous
      final totalMemory =
          (_totalRamProvider ?? SysInfo.getTotalPhysicalMemory)();
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
      final freeStorage = await (_freeStorageProvider ?? DiskUsage.freeSpace)();
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
