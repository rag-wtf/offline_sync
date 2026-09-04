import 'package:connectivity_plus/connectivity_plus.dart';
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
    expect(decision.reason, DownloadPolicyReason.insufficientStorage);
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
    expect(decision.reason, DownloadPolicyReason.connectivityUnknown);
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
        expect(
          decision.reason,
          connectivity == DownloadConnectivity.metered
              ? DownloadPolicyReason.meteredConsent
              : DownloadPolicyReason.unmeteredConsent,
        );
      }
    },
  );

  group('production connectivity provider', () {
    final cases =
        <({List<ConnectivityResult> results, DownloadConnectivity expected})>[
          (
            results: [ConnectivityResult.wifi],
            expected: DownloadConnectivity.unmetered,
          ),
          (
            results: [ConnectivityResult.ethernet],
            expected: DownloadConnectivity.unmetered,
          ),
          (
            results: [ConnectivityResult.mobile],
            expected: DownloadConnectivity.metered,
          ),
          (
            results: [ConnectivityResult.other],
            expected: DownloadConnectivity.metered,
          ),
          (
            results: [ConnectivityResult.satellite],
            expected: DownloadConnectivity.metered,
          ),
          (
            results: [ConnectivityResult.bluetooth],
            expected: DownloadConnectivity.metered,
          ),
          (
            results: [ConnectivityResult.none],
            expected: DownloadConnectivity.unknown,
          ),
          (
            results: [ConnectivityResult.vpn],
            expected: DownloadConnectivity.unknown,
          ),
          (results: [], expected: DownloadConnectivity.unknown),
          (
            results: [ConnectivityResult.vpn, ConnectivityResult.wifi],
            expected: DownloadConnectivity.unmetered,
          ),
        ];

    for (final entry in cases) {
      test('${entry.results} maps to ${entry.expected.name}', () async {
        final decision =
            await DownloadPolicyService(
              connectivityResultsProvider: () async => entry.results,
            ).evaluate(
              selected,
              const DeviceCapabilities(
                totalRamMB: 4096,
                availableStorageMB: 1024,
                hasGpu: true,
                platform: 'android',
              ),
            );

        expect(
          decision.reason,
          switch (entry.expected) {
            DownloadConnectivity.unmetered =>
              DownloadPolicyReason.unmeteredConsent,
            DownloadConnectivity.metered => DownloadPolicyReason.meteredConsent,
            DownloadConnectivity.unknown =>
              DownloadPolicyReason.connectivityUnknown,
          },
        );
      });
    }

    test('plugin failures fail closed as unknown connectivity', () async {
      final decision =
          await DownloadPolicyService(
            connectivityResultsProvider: () async =>
                throw StateError('offline'),
          ).evaluate(
            selected,
            const DeviceCapabilities(
              totalRamMB: 4096,
              availableStorageMB: 1024,
              hasGpu: true,
              platform: 'android',
            ),
          );

      expect(decision.allowed, isFalse);
      expect(decision.reason, DownloadPolicyReason.connectivityUnknown);
    });
  });
}
