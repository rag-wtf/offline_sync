import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/ui/dialogs/download_consent_dialog.dart';

void main() {
  testWidgets(
    'shows the localized metered warning with model names and sizes',
    (
      tester,
    ) async {
      const selected = RecommendedModels(
        inferenceModel: InferenceModels.gemma3_270M,
        embeddingModel: EmbeddingModels.gecko64,
        tier: DeviceTier.low,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DownloadConsentDialog(
            request: const DownloadConsentRequest(
              selected: selected,
              smallerCompatible: null,
              reason: DownloadPolicyReason.meteredConsent,
            ),
            onCompleted: ({required approved, useSmallerCompatible = false}) {},
          ),
        ),
      );

      expect(
        find.text(
          'Esta conexión puede tener límites de datos. Confirma la descarga.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${InferenceModels.gemma3_270M.name} '
          '(${InferenceModels.gemma3_270M.sizeFormatted})',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${EmbeddingModels.gecko64.name} '
          '(${EmbeddingModels.gecko64.sizeFormatted})',
        ),
        findsOneWidget,
      );
    },
  );
}
