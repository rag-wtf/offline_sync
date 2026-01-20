# Resource Monitoring Improvements - Implementation Plan

Improve the reliability of System RAM (Memory) and Storage detection based on findings from `docs/resource_monitoring.md`.

## User Review Required

> [!IMPORTANT]
> This change introduces two new dependencies: `disk_usage` and `system_info2`. These are recommended for improved reliability over `system_info_plus`.

## Background & Problem Analysis

The current `DeviceCapabilityService` has the following limitations:

1. **Hardcoded storage values**: Storage (`availableStorageMB`) is hardcoded (e.g., 4096MB for mobile, 10240MB for desktop)
2. **Suboptimal memory detection**: Uses `system_info_plus` which is less reliable than `system_info2` (FFI-based)
3. **No platform-specific handling**: Missing iOS memory compression considerations and Android sandbox limitations

**Composite Architecture Recommendation:**
- **Storage**: `disk_usage` - supports all 5 native platforms with proper platform-specific implementations (StatFs on Android, statvfs on Linux/macOS)
- **Memory**: `system_info2` - uses FFI for high-performance direct kernel access
- **Device Metadata**: `device_info_plus` (keep) - for model, platform info

---

## Proposed Changes

### Dependencies

#### [MODIFY] [pubspec.yaml](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/pubspec.yaml)

```diff
 dependencies:
+  disk_usage: ^1.0.0          # Storage detection for all native platforms
+  system_info2: ^4.1.0        # FFI-based memory detection (high performance)
   device_info_plus: ^12.3.0   # Keep for device metadata
-  system_info_plus: ^0.0.6    # Replace with system_info2
```

---

### DeviceCapabilityService Refactoring

#### [MODIFY] [device_capability_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/device_capability_service.dart)

**Key changes:**
1. Replace `SystemInfoPlus.physicalMemory` with `SysInfo.getTotalPhysicalMemory()`
2. Add dynamic storage detection using `DiskUsage.freeSpace()`
3. Add platform-specific reliability notes in documentation
4. Improve fallback handling with validation thresholds

**Correct API Usage:**

| Package | Method | Returns |
|---------|--------|---------|
| `disk_usage` | `DiskUsage.totalSpace()` | `Future<int?>` bytes |
| `disk_usage` | `DiskUsage.freeSpace()` | `Future<int?>` bytes |
| `system_info2` | `SysInfo.getTotalPhysicalMemory()` | `int` bytes (sync) |
| `system_info2` | `SysInfo.getFreePhysicalMemory()` | `int` bytes (sync) |

**Implementation changes for each platform method:**

```dart
// Import changes
import 'package:disk_usage/disk_usage.dart';
import 'package:system_info2/system_info2.dart';
// Remove: import 'package:system_info_plus/system_info_plus.dart';

// Constants for validation
static const int _minReasonableRamMB = 512;
static const int _minReasonableStorageMB = 100;

// For RAM detection (all native platforms):
var ramMB = fallbackValue;
try {
  // SysInfo.getTotalPhysicalMemory() is synchronous and returns int
  final totalMemory = SysInfo.getTotalPhysicalMemory();
  if (totalMemory > 0) {
    final calculatedRam = totalMemory ~/ (1024 * 1024);
    if (calculatedRam >= _minReasonableRamMB) {
      ramMB = calculatedRam;
    }
  }
} on Object catch (e) {
  log('Error detecting RAM: $e');
}

// For Storage detection (all native platforms):
var storageMB = fallbackValue;
try {
  // DiskUsage.freeSpace() is async and returns Future<int?>
  final freeStorage = await DiskUsage.freeSpace();
  if (freeStorage != null && freeStorage > 0) {
    final calculatedStorage = freeStorage ~/ (1024 * 1024);
    if (calculatedStorage >= _minReasonableStorageMB) {
      storageMB = calculatedStorage;
    }
  }
} on Object catch (e) {
  // May fail on Android 10+ outside app sandbox
  log('Error detecting storage: $e');
}
```

---

### Platform-Specific Considerations

#### iOS Warning (Critical)

> [!WARNING]
> **iOS Compressed Memory**: iOS uses memory compression. "Free RAM" is often near zero because iOS keeps apps compressed in memory.
> 
> **DO NOT use `SysInfo.getFreePhysicalMemory()` on iOS** for allocation decisions.
> 
> **Strategy**: Only use `getTotalPhysicalMemory()` for device tier categorization.

#### Android Storage Permissions

> [!NOTE]
> `disk_usage` works reliably for the app's internal sandbox. Querying paths outside the app sandbox (e.g., `/storage/emulated/0`) may fail on Android 10+ without `MANAGE_EXTERNAL_STORAGE` permission.

#### Web Platform

Web platform continues to use conservative defaults since `disk_usage` and `system_info2` don't support web. This matches the current implementation and the document's guidance that Web detection is inherently limited.

---

## Full Implementation

#### [MODIFY] [device_capability_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/device_capability_service.dart)

Complete replacement with all platform methods updated:

```dart
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
```

---

## Update Tests

#### [MODIFY] [device_capability_service_test.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/test/services/device_capability_service_test.dart)

The existing tests verify the RAM calculation logic which remains the same. Tests should continue to pass since we're only changing the data source, not the calculation/validation logic.

---

## Verification Plan

### Automated Tests

```bash
# Install new dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run all tests
flutter test
```

### Manual Verification

1. **Linux**: Run app, verify RAM and Storage display correct values in Settings
   - Compare RAM with `free -m` command
   - Compare Storage with `df -h` command

2. **Android** (if available): Deploy to device, verify values match device settings

---

## Summary of Changes

| File | Action | Description |
|------|--------|-------------|
| `pubspec.yaml` | MODIFY | Add `disk_usage: ^1.0.0`, `system_info2: ^4.1.0`; remove `system_info_plus` |
| `device_capability_service.dart` | MODIFY | Use `SysInfo` for RAM, `DiskUsage` for storage; add helper methods |
| `device_capability_service_test.dart` | NO CHANGE | Existing tests remain valid |
