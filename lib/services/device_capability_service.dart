import 'dart:developer';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

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

/// Service to detect device capabilities
class DeviceCapabilityService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

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
      totalRamMB: 2048, // 2GB default
      availableStorageMB: 1024, // 1GB default
      hasGpu: false,
      platform: 'unknown',
    );
  }

  Future<DeviceCapabilities> _getWebCapabilities() async {
    // Web platform: Use conservative defaults since we can't reliably
    // detect RAM/storage. Use smallest models for web.
    log('Web platform detected, using conservative defaults');
    return const DeviceCapabilities(
      totalRamMB: 2048, // Conservative 2GB
      availableStorageMB: 2048, // Conservative 2GB
      hasGpu: false, // Web doesn't expose GPU info reliably
      platform: 'web',
    );
  }

  Future<DeviceCapabilities> _getAndroidCapabilities() async {
    final androidInfo = await _deviceInfo.androidInfo;

    // Try to get memory info from system_info_plus
    // Note: This requires system_info_plus package which may not work on all
    // Android versions. We'll use a conservative estimate if it fails.
    const ramMB = 4096; // Default to 4GB if we can't detect

    // Android builds often have totalMemory in systemFeatures
    // but it's not always reliable. For now, use conservative default.
    log('Android device: ${androidInfo.model}');

    return const DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 4096, // Conservative estimate
      hasGpu: true, // Most modern Android devices have GPU
      platform: 'android',
    );
  }

  Future<DeviceCapabilities> _getIosCapabilities() async {
    final iosInfo = await _deviceInfo.iosInfo;

    // iOS devices typically have good specs
    // Map based on device model if needed
    const ramMB = 4096; // Conservative default for iOS

    log('iOS device: ${iosInfo.model}');

    return const DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 4096,
      hasGpu: true, // iOS devices have GPU
      platform: 'ios',
    );
  }

  Future<DeviceCapabilities> _getLinuxCapabilities() async {
    final linuxInfo = await _deviceInfo.linuxInfo;

    log('Linux device: ${linuxInfo.prettyName}');

    // For Linux desktop, assume reasonable specs
    return const DeviceCapabilities(
      totalRamMB: 8192, // 8GB default for desktop
      availableStorageMB: 10240, // 10GB
      hasGpu: true, // Desktop likely has GPU
      platform: 'linux',
    );
  }

  Future<DeviceCapabilities> _getMacOsCapabilities() async {
    final macInfo = await _deviceInfo.macOsInfo;

    log('macOS device: ${macInfo.model}');

    // macOS devices typically have good specs
    return const DeviceCapabilities(
      totalRamMB: 8192, // 8GB default
      availableStorageMB: 10240,
      hasGpu: true,
      platform: 'macos',
    );
  }

  Future<DeviceCapabilities> _getWindowsCapabilities() async {
    final windowsInfo = await _deviceInfo.windowsInfo;

    log('Windows device: ${windowsInfo.computerName}');

    return const DeviceCapabilities(
      totalRamMB: 8192, // 8GB default for desktop
      availableStorageMB: 10240,
      hasGpu: true,
      platform: 'windows',
    );
  }
}
