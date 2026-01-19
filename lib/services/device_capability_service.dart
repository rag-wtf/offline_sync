import 'dart:developer';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:system_info_plus/system_info_plus.dart';

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
    log('Android device: ${androidInfo.model}');

    var ramMB = 2048; // Safe fallback
    try {
      final totalMemory = await SystemInfoPlus.physicalMemory;
      if (totalMemory != null && totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }
    } on Object catch (e) {
      log('Error detecting Android RAM: $e');
    }

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 4096, // Conservative estimate
      hasGpu: true, // Most modern Android devices have GPU
      platform: 'android',
    );
  }

  Future<DeviceCapabilities> _getIosCapabilities() async {
    final iosInfo = await _deviceInfo.iosInfo;
    log('iOS device: ${iosInfo.model}');

    var ramMB = 2048; // Safe fallback
    try {
      final totalMemory = await SystemInfoPlus.physicalMemory;
      if (totalMemory != null && totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }
    } on Object catch (e) {
      log('Error detecting iOS RAM: $e');
    }

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 4096,
      hasGpu: true, // iOS devices have GPU
      platform: 'ios',
    );
  }

  Future<DeviceCapabilities> _getLinuxCapabilities() async {
    final linuxInfo = await _deviceInfo.linuxInfo;
    log('Linux device: ${linuxInfo.prettyName}');

    var ramMB = 4096; // Safe fallback for desktop
    try {
      final totalMemory = await SystemInfoPlus.physicalMemory;
      if (totalMemory != null && totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }
    } on Object catch (e) {
      log('Error detecting Linux RAM: $e');
    }

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 10240, // 10GB
      hasGpu: true, // Desktop likely has GPU
      platform: 'linux',
    );
  }

  Future<DeviceCapabilities> _getMacOsCapabilities() async {
    final macInfo = await _deviceInfo.macOsInfo;
    log('macOS device: ${macInfo.model}');

    var ramMB = 4096; // Safe fallback
    try {
      final totalMemory = await SystemInfoPlus.physicalMemory;
      if (totalMemory != null && totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }
    } on Object catch (e) {
      log('Error detecting macOS RAM: $e');
    }

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 10240,
      hasGpu: true,
      platform: 'macos',
    );
  }

  Future<DeviceCapabilities> _getWindowsCapabilities() async {
    final windowsInfo = await _deviceInfo.windowsInfo;
    log('Windows device: ${windowsInfo.computerName}');

    var ramMB = 4096; // Safe fallback
    try {
      final totalMemory = await SystemInfoPlus.physicalMemory;
      if (totalMemory != null && totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }
    } on Object catch (e) {
      log('Error detecting Windows RAM: $e');
    }

    return DeviceCapabilities(
      totalRamMB: ramMB,
      availableStorageMB: 10240,
      hasGpu: true,
      platform: 'windows',
    );
  }
}
