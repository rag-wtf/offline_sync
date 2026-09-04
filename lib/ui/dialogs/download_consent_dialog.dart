import 'package:flutter/material.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/download_policy_service.dart';

class DownloadConsentDialog extends StatelessWidget {
  const DownloadConsentDialog({
    required this.request,
    required this.onCompleted,
    super.key,
  });

  final DownloadConsentRequest request;
  final void Function({required bool approved, bool useSmallerCompatible})
  onCompleted;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final smaller = request.smallerCompatible;
    return AlertDialog(
      title: Text(strings.downloadConsentTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.downloadConsentDescription),
            const SizedBox(height: 8),
            for (final model in request.selectedModels)
              Text('${model.name} (${model.sizeFormatted})'),
            const SizedBox(height: 12),
            Text(request.reason),
            if (smaller != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => onCompleted(
                  approved: true,
                  useSmallerCompatible: true,
                ),
                child: Text(strings.downloadConsentUseSmaller),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => onCompleted(approved: false),
          child: Text(strings.cancelAction),
        ),
        ElevatedButton(
          onPressed: () => onCompleted(approved: true),
          child: Text(strings.downloadConsentDownload),
        ),
      ],
    );
  }
}
