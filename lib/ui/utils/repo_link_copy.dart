import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> copyRepoLinkToClipboard(
  BuildContext context,
  String repoPage,
) async {
  await Clipboard.setData(ClipboardData(text: repoPage));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Repo link copied to clipboard')),
    );
}
