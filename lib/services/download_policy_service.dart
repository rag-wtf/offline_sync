import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';

/// The known cost of the active connection. Unknown is deliberately unsafe
/// for automatic model downloads.
enum DownloadConnectivity { unmetered, metered, unknown }

/// Stable outcomes that presentation layers translate into user-facing copy.
enum DownloadPolicyReason {
  insufficientStorage,
  connectivityUnknown,
  meteredConsent,
  unmeteredConsent,
  consentDenied,
}

class DownloadPolicyDecision {
  const DownloadPolicyDecision._({
    required this.allowed,
    required this.reason,
    required this.requiresConsent,
  });

  const DownloadPolicyDecision.allowed({
    required DownloadPolicyReason reason,
    required bool requiresConsent,
  }) : this._(allowed: true, reason: reason, requiresConsent: requiresConsent);

  const DownloadPolicyDecision.denied(DownloadPolicyReason reason)
    : this._(allowed: false, reason: reason, requiresConsent: false);

  final bool allowed;
  final DownloadPolicyReason reason;
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
  final DownloadPolicyReason reason;

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
    Future<List<ConnectivityResult>> Function()? connectivityResultsProvider,
  }) : _connectivityProvider =
           connectivityProvider ??
           _pluginConnectivityProvider(connectivityResultsProvider);

  final Future<DownloadConnectivity> Function() _connectivityProvider;

  static Future<DownloadConnectivity> Function() _pluginConnectivityProvider(
    Future<List<ConnectivityResult>> Function()? resultsProvider,
  ) {
    final provider = resultsProvider ?? Connectivity().checkConnectivity;
    return () => _connectivityFromPlugin(provider);
  }

  static Future<DownloadConnectivity> _connectivityFromPlugin(
    Future<List<ConnectivityResult>> Function() resultsProvider,
  ) async {
    try {
      return _classifyConnectivity(await resultsProvider());
    } on Object {
      return DownloadConnectivity.unknown;
    }
  }

  static DownloadConnectivity _classifyConnectivity(
    List<ConnectivityResult> results,
  ) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return DownloadConnectivity.unmetered;
    }
    if (results.contains(ConnectivityResult.mobile) ||
        results.contains(ConnectivityResult.other) ||
        results.contains(ConnectivityResult.bluetooth) ||
        results.contains(ConnectivityResult.satellite)) {
      return DownloadConnectivity.metered;
    }
    return DownloadConnectivity.unknown;
  }

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
        DownloadPolicyReason.insufficientStorage,
      );
    }

    final connectivity = await _connectivityProvider();
    if (connectivity == DownloadConnectivity.unknown) {
      return const DownloadPolicyDecision.denied(
        DownloadPolicyReason.connectivityUnknown,
      );
    }

    final reason = connectivity == DownloadConnectivity.metered
        ? DownloadPolicyReason.meteredConsent
        : DownloadPolicyReason.unmeteredConsent;
    return DownloadPolicyDecision.allowed(
      reason: reason,
      requiresConsent: true,
    );
  }
}
