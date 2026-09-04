import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';

/// The known cost of the active connection. Unknown is deliberately unsafe
/// for automatic model downloads.
enum DownloadConnectivity { unmetered, metered, unknown }

class DownloadPolicyDecision {
  const DownloadPolicyDecision._({
    required this.allowed,
    required this.reason,
    required this.requiresConsent,
  });

  const DownloadPolicyDecision.allowed({
    required String reason,
    required bool requiresConsent,
  }) : this._(allowed: true, reason: reason, requiresConsent: requiresConsent);

  const DownloadPolicyDecision.denied(String reason)
    : this._(allowed: false, reason: reason, requiresConsent: false);

  final bool allowed;
  final String reason;
  final bool requiresConsent;
}

class DownloadConsentRequest {
  const DownloadConsentRequest({
    required this.selected,
    required this.smallerCompatible,
    required this.reason,
  });

  final RecommendedModels selected;
  final RecommendedModels? smallerCompatible;
  final String reason;

  List<ModelDefinition> get selectedModels => [
    selected.inferenceModel,
    selected.embeddingModel,
  ];
}

class DownloadConsentResult {
  const DownloadConsentResult({
    required this.approved,
    this.useSmallerCompatible = false,
  });

  final bool approved;
  final bool useSmallerCompatible;
}

typedef DownloadConsentPrompter =
    Future<DownloadConsentResult> Function(
      DownloadConsentRequest request,
    );

/// Guardrail for first-run downloads. It performs no network activity and is
/// intentionally injectable so startup can be tested without device plugins.
class DownloadPolicyService {
  DownloadPolicyService({
    Future<DownloadConnectivity> Function()? connectivityProvider,
  }) : _connectivityProvider = connectivityProvider ?? _unknownConnectivity;

  final Future<DownloadConnectivity> Function() _connectivityProvider;

  static Future<DownloadConnectivity> _unknownConnectivity() async =>
      DownloadConnectivity.unknown;

  Future<DownloadPolicyDecision> evaluate(
    List<ModelDefinition> selectedModels,
    DeviceCapabilities capabilities,
  ) async {
    final selectedBytes = selectedModels.fold<int>(
      0,
      (total, model) => total + model.sizeBytes,
    );
    final freeBytes = capabilities.availableStorageMB * 1024 * 1024;
    if (selectedBytes > freeBytes) {
      return const DownloadPolicyDecision.denied(
        'Not enough free storage for the selected models.',
      );
    }

    final connectivity = await _connectivityProvider();
    if (connectivity == DownloadConnectivity.unknown) {
      return const DownloadPolicyDecision.denied(
        'Downloads are paused because the connection type could not be '
        'determined.',
      );
    }

    final reason = connectivity == DownloadConnectivity.metered
        ? 'This connection may be metered. Confirm the model download.'
        : 'Confirm the model download.';
    return DownloadPolicyDecision.allowed(
      reason: reason,
      requiresConsent: true,
    );
  }
}
