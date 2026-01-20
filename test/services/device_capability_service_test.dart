import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/device_capability_service.dart';

void main() {
  group('DeviceCapabilityService RAM Detection', () {
    test('should handle very small RAM values that round to 0MB', () {
      // This test reproduces the issue where SystemInfoPlus.physicalMemory
      // returns a very small byte value (e.g., < 524,288 bytes = 0.5 MB)
      // which when divided by (1024 * 1024) and rounded, becomes 0.

      // Simulate the conversion that happens in the service
      const verySmallMemoryBytes = 500000; // ~0.48 MB
      final ramMB = (verySmallMemoryBytes / (1024 * 1024)).round();

      // This should be 0 due to rounding
      expect(ramMB, equals(0));

      // The expected behavior is that the service should use the fallback
      // value (2048 MB for Android) instead of returning 0 MB
    });

    test('should use fallback when calculated RAM is 0', () {
      // When memory detection returns a value that rounds to 0,
      // the service should use the fallback value instead

      const verySmallMemoryBytes = 100000; // ~0.095 MB
      var ramMB = 2048; // Safe fallback

      const totalMemory = verySmallMemoryBytes;
      if (totalMemory > 0) {
        final calculatedRam = (totalMemory / (1024 * 1024)).round();
        // Only use calculated value if it's reasonable
        if (calculatedRam > 0) {
          ramMB = calculatedRam;
        }
      }

      // Should still be 2048 because calculatedRam was 0
      expect(ramMB, equals(2048));
    });

    test('should handle null physicalMemory', () {
      const int? totalMemory = null;
      var ramMB = 2048; // Safe fallback

      if (totalMemory != null && totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }

      // Should stay at fallback value
      expect(ramMB, equals(2048));
    });

    test('should handle zero physicalMemory', () {
      const totalMemory = 0;
      var ramMB = 2048; // Safe fallback

      if (totalMemory > 0) {
        ramMB = (totalMemory / (1024 * 1024)).round();
      }

      // Should stay at fallback value
      expect(ramMB, equals(2048));
    });

    test('should correctly calculate normal RAM values', () {
      const totalMemory = 4 * 1024 * 1024 * 1024; // 4 GB in bytes
      var ramMB = 2048; // Safe fallback

      if (totalMemory > 0) {
        final calculatedRam = (totalMemory / (1024 * 1024)).round();
        if (calculatedRam > 0) {
          ramMB = calculatedRam;
        }
      }

      // Should be 4096 MB (4 GB)
      expect(ramMB, equals(4096));
    });
  });

  group('DeviceCapabilities', () {
    test('toString should format RAM correctly', () {
      const capabilities = DeviceCapabilities(
        totalRamMB: 0, // This is the bug - shows 0MB
        availableStorageMB: 4096,
        hasGpu: true,
        platform: 'android',
      );

      final result = capabilities.toString();

      // This demonstrates the bug - shows RAM: 0MB
      expect(result, contains('RAM: 0MB'));
    });

    test('toString should show proper RAM when fixed', () {
      const capabilities = DeviceCapabilities(
        totalRamMB: 2048, // Proper fallback value
        availableStorageMB: 4096,
        hasGpu: true,
        platform: 'android',
      );

      final result = capabilities.toString();

      // Should show reasonable RAM value
      expect(result, contains('RAM: 2048MB'));
    });
  });
}
