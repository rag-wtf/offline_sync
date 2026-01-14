import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/model_config.dart';

class EmbeddingService {
  bool _isInitialized = false;

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

      const config = ModelConfig.embeddingModel;

      try {
        final token = await AuthTokenService.loadToken();

        await FlutterGemma.installEmbedder()
            .modelFromNetwork(config.modelUrl, token: token)
            .tokenizerFromNetwork(config.tokenizerUrl!, token: token)
            .install();

        _isInitialized = true;
        debugPrint('[EmbeddingService] Default embedder initialized. ✅');
      } catch (e) {
        debugPrint(
          '[EmbeddingService] Failed to initialize default embedder: $e',
        );

        // Check if it's an authentication error
        final errorMsg = e.toString();
        if (errorMsg.contains('401') || errorMsg.contains('Unauthorized')) {
          throw AuthenticationRequiredException(
            'Hugging Face authentication required. '
            'Please provide a valid token.',
          );
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
