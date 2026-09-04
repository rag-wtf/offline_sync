import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/services/model_config.dart';

void main() {
  const selected = <ModelDefinition>[
    InferenceModels.gemma3_270M,
    EmbeddingModels.gecko64,
  ];

  test('rejects a selected pair that exceeds available storage', () async {
    final decision =
        await DownloadPolicyService(
          connectivityProvider: () async => DownloadConnectivity.unmetered,
        ).evaluate(
          selected,
          const DeviceCapabilities(
            totalRamMB: 4096,
            availableStorageMB: 300,
            hasGpu: true,
            platform: 'android',
          ),
        );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('Not enough free storage'));
  });

  test('rejects unknown connectivity before requesting consent', () async {
    final decision = await DownloadPolicyService().evaluate(
      selected,
      const DeviceCapabilities(
        totalRamMB: 4096,
        availableStorageMB: 1024,
        hasGpu: true,
        platform: 'android',
      ),
    );

    expect(decision.allowed, isFalse);
    expect(
      decision.reason,
      contains('connection type could not be determined'),
    );
  });

  test(
    'requires explicit consent on metered and unmetered connections',
    () async {
      for (final connectivity in <DownloadConnectivity>[
        DownloadConnectivity.metered,
        DownloadConnectivity.unmetered,
      ]) {
        final decision =
            await DownloadPolicyService(
              connectivityProvider: () async => connectivity,
            ).evaluate(
              selected,
              const DeviceCapabilities(
                totalRamMB: 4096,
                availableStorageMB: 1024,
                hasGpu: true,
                platform: 'android',
              ),
            );

        expect(decision.allowed, isTrue);
        expect(decision.requiresConsent, isTrue);
      }
    },
  );
}
