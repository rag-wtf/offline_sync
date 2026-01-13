import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:url_launcher/url_launcher.dart';

class TokenInputDialog extends StatefulWidget {
  const TokenInputDialog({super.key});

  @override
  State<TokenInputDialog> createState() => _TokenInputDialogState();
}

class _TokenInputDialogState extends State<TokenInputDialog> {
  final TextEditingController _tokenController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;

    setState(() => _isSaving = true);

    await AuthTokenService.saveToken(token);

    if (mounted) {
      Navigator.of(context).pop(true); // Return true to indicate success
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Authentication Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The selected embedding model requires a Hugging Face '
            'Access Token.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Hugging Face Access Token',
              hintText: 'hf_...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall,
              text: 'Manage your tokens at ',
              children: [
                TextSpan(
                  text: 'huggingface.co/settings/tokens',
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      unawaited(
                        launchUrl(
                          Uri.parse('https://huggingface.co/settings/tokens'),
                        ),
                      );
                    },
                ),
                const TextSpan(text: '. Ensure the token has read access.'),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
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
