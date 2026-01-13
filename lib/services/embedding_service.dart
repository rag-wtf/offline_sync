import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked_services/stacked_services.dart';

class EmbeddingService {
  bool _isInitialized = false;
  final NavigationService _navigationService = locator<NavigationService>();

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    try {
      // Check if an embedder is already active.
      // If this call succeeds, we are good.
      await FlutterGemma.getActiveEmbedder();
      _isInitialized = true;
    } on Object {
      // If it fails, we need to install one.
      debugPrint(
        '[EmbeddingService] No active embedder found. Initializing default...',
      );

      const modelUrl =
          'https://huggingface.co/litert-community/embeddinggemma-300m/'
          'resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
      const tokenizerUrl =
          'https://huggingface.co/litert-community/embeddinggemma-300m/'
          'resolve/main/sentencepiece.model';

      try {
        final token = await AuthTokenService.loadToken();

        await FlutterGemma.installEmbedder()
            .modelFromNetwork(modelUrl, token: token)
            .tokenizerFromNetwork(tokenizerUrl, token: token)
            .install();

        _isInitialized = true;
        debugPrint('[EmbeddingService] Default embedder initialized. ✅');
      } catch (e) {
        debugPrint(
          '[EmbeddingService] Failed to initialize default embedder: $e',
        );

        // Use the navigation service context to show the dialog.
        // navigatorKey is used to access current context from service.
        // ignore: deprecated_member_use
        final context = _navigationService.navigatorKey?.currentContext;
        if (context != null && context.mounted) {
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const TokenInputDialog(),
          );

          if (result ?? false) {
            // Token saved, retry initialization
            debugPrint('[EmbeddingService] Token provided, retrying init...');
            return _ensureInitialized();
          }
        }

        rethrow;
      }
    }
  }

  Future<List<double>> generateEmbedding(String text) async {
    await _ensureInitialized();
    final embedder = await FlutterGemma.getActiveEmbedder();

    // Note: getEmbedding might return a List<double> or a proprietary object
    // depending on version. Standardizing to List<double>.
    // Using dynamic to bypass analyzer issues with library types.
    final result = await embedder.generateEmbedding(text);
    return result;
  }
}
