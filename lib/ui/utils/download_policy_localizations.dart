import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/download_policy_service.dart';

String localizeDownloadPolicyReason(
  AppLocalizations strings,
  DownloadPolicyReason reason,
) => switch (reason) {
  DownloadPolicyReason.insufficientStorage =>
    strings.downloadPolicyInsufficientStorage,
  DownloadPolicyReason.connectivityUnknown =>
    strings.downloadPolicyConnectivityUnknown,
  DownloadPolicyReason.meteredConsent => strings.downloadPolicyMeteredConsent,
  DownloadPolicyReason.unmeteredConsent =>
    strings.downloadPolicyUnmeteredConsent,
  DownloadPolicyReason.consentDenied => strings.downloadPolicyConsentDenied,
};
