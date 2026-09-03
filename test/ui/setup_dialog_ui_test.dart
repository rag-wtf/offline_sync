import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
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
}
