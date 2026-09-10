import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/ui/dialogs/download_consent_dialog.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:offline_sync/ui/setup_dialog_ui.dart';
import 'package:stacked_services/stacked_services.dart';

class RecordingDialogService extends DialogService {
  Map<dynamic, DialogBuilder>? registeredBuilders;

  @override
  void registerCustomDialogBuilders(Map<dynamic, DialogBuilder> builders) {
    registeredBuilders = builders;
  }
}

void main() {
  testWidgets('registers the token dialog with request data and completion', (
    tester,
  ) async {
    await locator.reset();
    addTearDown(locator.reset);

    final dialogService = RecordingDialogService();
    locator.registerSingleton<DialogService>(dialogService);
    setupDialogUi();

    final builder = dialogService.registeredBuilders![DialogType.tokenInput]!;
    DialogResponse<dynamic>? response;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => builder(
            context,
            DialogRequest<dynamic>(
              data: const TokenInputDialogData(
                repoPage: 'https://huggingface.co/example/model',
                modelName: 'Example model',
              ),
            ),
            (value) => response = value,
          ),
        ),
      ),
    );

    final tokenDialog = tester.widget<TokenInputDialog>(
      find.byType(TokenInputDialog),
    );
    expect(tokenDialog.repoPage, 'https://huggingface.co/example/model');
    expect(tokenDialog.modelName, 'Example model');

    tokenDialog.onCompleted!(success: false);

    expect(response?.confirmed, isFalse);
  });

  testWidgets('handles setupDialogUi when DialogService is not registered', (
    tester,
  ) async {
    await locator.reset();
    addTearDown(locator.reset);
    setupDialogUi();
  });

  testWidgets('registers the downloadConsent dialog and handles callbacks', (
    tester,
  ) async {
    await locator.reset();
    addTearDown(locator.reset);

    final dialogService = RecordingDialogService();
    locator.registerSingleton<DialogService>(dialogService);
    setupDialogUi();

    final builder =
        dialogService.registeredBuilders![DialogType.downloadConsent]!;

    // Case 1: null data
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => builder(
            context,
            DialogRequest<dynamic>(),
            (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(SizedBox), findsOneWidget);

    // Case 2: valid data
    DialogResponse<dynamic>? response;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: builder(
              context,
              DialogRequest<dynamic>(
                data: const DownloadConsentDialogData(
                  request: DownloadConsentRequest(
                    modelsToDownload: [],
                    smallerCompatible: null,
                    reason: DownloadPolicyReason.meteredConsent,
                  ),
                ),
              ),
              (value) => response = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final consentDialog = tester.widget<DownloadConsentDialog>(
      find.byType(DownloadConsentDialog),
    );
    consentDialog.onCompleted(approved: true, useSmallerCompatible: true);
    expect(response?.confirmed, isTrue);
    expect(response?.data, isTrue);
  });
}
