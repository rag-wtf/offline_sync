import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/ui/dialogs/download_consent_dialog.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked_services/stacked_services.dart';

enum DialogType { tokenInput, downloadConsent }

class TokenInputDialogData {
  const TokenInputDialogData({this.repoPage, this.modelName});

  final String? repoPage;
  final String? modelName;
}

class DownloadConsentDialogData {
  const DownloadConsentDialogData({required this.request});

  final DownloadConsentRequest request;
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
    DialogType.downloadConsent: (context, request, completer) {
      final data = request.data as DownloadConsentDialogData?;
      if (data == null) return const SizedBox.shrink();
      return DownloadConsentDialog(
        request: data.request,
        onCompleted: ({required approved, useSmallerCompatible = false}) {
          completer(
            DialogResponse(
              confirmed: approved,
              data: useSmallerCompatible,
            ),
          );
          Navigator.of(context).pop();
        },
      );
    },
  };

  dialogService.registerCustomDialogBuilders(builders);
}
