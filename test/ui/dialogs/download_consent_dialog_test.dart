import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/ui/dialogs/download_consent_dialog.dart';

void main() {
  const testModel = InferenceModels.gemma3_270M;
  const smallerModel = EmbeddingModels.gecko64;

  Widget createWidget({
    required DownloadConsentRequest request,
    required void Function({
      required bool approved,
      bool useSmallerCompatible,
    })
    onCompleted,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DownloadConsentDialog(
          request: request,
          onCompleted: onCompleted,
        ),
      ),
    );
  }

  testWidgets('renders dialog and triggers cancel action', (tester) async {
    bool? wasApproved;
    bool? wasSmaller;

    const request = DownloadConsentRequest(
      modelsToDownload: [testModel],
      smallerCompatible: null,
      reason: DownloadPolicyReason.insufficientStorage,
    );

    await tester.pumpWidget(
      createWidget(
        request: request,
        onCompleted:
            ({
              required approved,
              useSmallerCompatible = false,
            }) {
              wasApproved = approved;
              wasSmaller = useSmallerCompatible;
            },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Gemma 3 270M IT'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(wasApproved, isFalse);
    expect(wasSmaller, isFalse);
  });

  testWidgets('renders dialog and triggers download and use-smaller actions', (
    tester,
  ) async {
    bool? wasApproved;
    bool? wasSmaller;

    const request = DownloadConsentRequest(
      modelsToDownload: [testModel],
      smallerCompatible: RecommendedModels(
        inferenceModel: testModel,
        embeddingModel: smallerModel,
        tier: DeviceTier.low,
      ),
      reason: DownloadPolicyReason.meteredConsent,
    );

    await tester.pumpWidget(
      createWidget(
        request: request,
        onCompleted:
            ({
              required approved,
              useSmallerCompatible = false,
            }) {
              wasApproved = approved;
              wasSmaller = useSmallerCompatible;
            },
      ),
    );
    await tester.pumpAndSettle();

    // Test use smaller compatible button
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(wasApproved, isTrue);
    expect(wasSmaller, isTrue);

    // Test direct download button
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(wasApproved, isTrue);
    expect(wasSmaller, isFalse);
  });
}
