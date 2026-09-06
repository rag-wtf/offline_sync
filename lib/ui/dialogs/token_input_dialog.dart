import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/l10n/gen/app_localizations_en.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/ui/utils/repo_link_copy.dart';
import 'package:url_launcher/url_launcher.dart';

class TokenInputDialog extends StatefulWidget {
  const TokenInputDialog({
    this.repoPage,
    this.modelName,
    this.onSaveToken,
    this.onLaunchUrl,
    this.onCompleted,
    super.key,
  });

  final String? repoPage;
  final String? modelName;
  final Future<void> Function(String token)? onSaveToken;
  final Future<bool> Function(Uri uri)? onLaunchUrl;
  final void Function({required bool success})? onCompleted;

  @override
  State<TokenInputDialog> createState() => _TokenInputDialogState();
}

class _TokenInputDialogState extends State<TokenInputDialog> {
  final TextEditingController _tokenController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  AppLocalizations get _localizations =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizationsEn();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();

    // Validate token is not empty
    if (token.isEmpty) {
      setState(() {
        _errorMessage = _localizations.tokenEmptyError;
      });
      return;
    }

    // Validate token format (HuggingFace tokens start with 'hf_')
    if (!token.startsWith('hf_')) {
      setState(() {
        _errorMessage = _localizations.tokenInvalidError;
      });
      return;
    }

    // Clear any previous error
    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });

    try {
      await (widget.onSaveToken ?? AuthTokenService.saveToken)(token);

      if (mounted) {
        widget.onCompleted?.call(success: true);
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _localizations.tokenSaveFailed(e);
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _localizations;
    return AlertDialog(
      title: Text(l10n.authRequiredTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.modelName != null
                  ? l10n.tokenRequiredForModel(widget.modelName!)
                  : l10n.tokenRequiredForSelectedModel,
            ),
            if (widget.repoPage case final repoPage?) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.bodySmall,
                  text: l10n.signInModelTerms,
                  children: [
                    TextSpan(
                      text: repoPage,
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        // coverage:ignore-start
                        ..onTap = () {
                          unawaited(
                            (widget.onLaunchUrl ?? launchUrl)(
                              Uri.parse(repoPage),
                            ),
                          );
                        },
                      // coverage:ignore-end
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => copyRepoLinkToClipboard(context, repoPage),
                    icon: const Icon(Icons.copy, size: 14),
                    label: Text(
                      l10n.copyRepoLinkAction,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.accessTokenLabel,
                hintText: l10n.hfTokenInputHint,
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: Theme.of(context).textTheme.bodySmall,
                text: l10n.createReadToken,
                children: [
                  TextSpan(
                    text: 'huggingface.co/settings/tokens',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      // coverage:ignore-start
                      ..onTap = () {
                        unawaited(
                          (widget.onLaunchUrl ?? launchUrl)(
                            Uri.parse('https://huggingface.co/settings/tokens'),
                          ),
                        );
                      },
                    // coverage:ignore-end
                  ),
                  TextSpan(
                    text: l10n.sameAcceptedAccount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.fineGrainedTokenRequirement,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        // coverage:ignore-start
        TextButton(
          onPressed: () {
            widget.onCompleted?.call(success: false);
            Navigator.of(context).pop(false);
          },
          child: Text(l10n.cancelAction),
        ),
        // coverage:ignore-end
        ElevatedButton(
          onPressed: _isSaving ? null : _saveToken,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.saveContinueAction),
        ),
      ],
    );
  }
}
