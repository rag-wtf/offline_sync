import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked_services/stacked_services.dart';

enum DialogType { tokenInput }

void setupDialogUi() {
  if (!locator.isRegistered<DialogService>()) {
    return;
  }
  final dialogService = locator<DialogService>();

  final builders = <dynamic, DialogBuilder>{
    DialogType.tokenInput: (context, request, completer) {
      final data = request.data as Map<String, dynamic>?;
      return Dialog(
        backgroundColor: Colors.transparent,
        child: TokenInputDialog(
          repoPage: data?['repoPage'] as String?,
          modelName: data?['modelName'] as String?,
          onCompleted: ({required success}) =>
              completer(DialogResponse(confirmed: success)),
        ),
      );
    },
  };

  dialogService.registerCustomDialogBuilders(builders);
}
