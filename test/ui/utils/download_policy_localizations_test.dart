import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/l10n/gen/app_localizations_en.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/ui/utils/download_policy_localizations.dart';

void main() {
  final strings = AppLocalizationsEn();

  test('localizes all download policy reasons', () {
    expect(
      localizeDownloadPolicyReason(
        strings,
        DownloadPolicyReason.insufficientStorage,
      ),
      strings.downloadPolicyInsufficientStorage,
    );
    expect(
      localizeDownloadPolicyReason(
        strings,
        DownloadPolicyReason.connectivityUnknown,
      ),
      strings.downloadPolicyConnectivityUnknown,
    );
    expect(
      localizeDownloadPolicyReason(
        strings,
        DownloadPolicyReason.meteredConsent,
      ),
      strings.downloadPolicyMeteredConsent,
    );
    expect(
      localizeDownloadPolicyReason(
        strings,
        DownloadPolicyReason.unmeteredConsent,
      ),
      strings.downloadPolicyUnmeteredConsent,
    );
    expect(
      localizeDownloadPolicyReason(
        strings,
        DownloadPolicyReason.consentDenied,
      ),
      strings.downloadPolicyConsentDenied,
    );
  });
}
