import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked_services/stacked_services.dart';

enum DialogType { tokenInput }

class TokenInputDialogData {
  const TokenInputDialogData({this.repoPage, this.modelName});

  final String? repoPage;
  final String? modelName;
}

void setupDialogUi() {
  if (!locator.isRegistered<DialogService>()) {
    return;
  }
  final dialogService = locator<DialogService>();

  final builders = <dynamic, DialogBuilder>{
    DialogType.tokenInput: (context, request, completer) {
      final data = request.data as TokenInputDialogData?;
      return Dialog(
        backgroundColor: Colors.transparent,
        child: TokenInputDialog(
          repoPage: data?.repoPage,
          modelName: data?.modelName,
          onCompleted: ({required success}) =>
              completer(DialogResponse(confirmed: success)),
        ),
      );
    },
  };

  dialogService.registerCustomDialogBuilders(builders);
}
