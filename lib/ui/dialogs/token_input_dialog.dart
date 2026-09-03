import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
        _errorMessage = 'Token cannot be empty';
      });
      return;
    }

    // Validate token format (HuggingFace tokens start with 'hf_')
    if (!token.startsWith('hf_')) {
      setState(() {
        _errorMessage =
            'Invalid token format. HuggingFace tokens should start with "hf_"';
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
          _errorMessage = 'Failed to save token: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Authentication Required'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.modelName != null
                  ? '${widget.modelName} requires a Hugging Face Access Token.'
                  : 'The selected model requires a Hugging Face Access Token.',
            ),
            if (widget.repoPage case final repoPage?) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.bodySmall,
                  text: 'Sign in and accept the model terms at ',
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
                    label: const Text(
                      'Copy repo link',
                      style: TextStyle(fontSize: 12),
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
                labelText: 'Hugging Face Access Token',
                hintText: 'hf_...',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: Theme.of(context).textTheme.bodySmall,
                text: 'Create a read token at ',
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
                  const TextSpan(
                    text: ', using the same account that accepted the terms.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A fine-grained token also needs "Read access to the contents '
              'of all public gated repos you can access".',
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
          child: const Text('Cancel'),
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
              : const Text('Save & Continue'),
        ),
      ],
    );
  }
}
