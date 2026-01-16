import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';

class ContextualizedChunk {
  const ContextualizedChunk({
    required this.originalContent,
    required this.context,
    required this.combinedContent,
  });

  final String originalContent;
  final String context;
  final String combinedContent;
}

class ContextualRetrievalService {
  final DeviceCapabilityService _deviceService =
      locator<DeviceCapabilityService>();
  final ModelRecommendationService _recommendationService =
      locator<ModelRecommendationService>();
  final RagSettingsService _settingsService = locator<RagSettingsService>();

  // Only supported on High or Premium tiers due to context window requirements
  Future<bool> get isSupported async {
    // If explicitly disabled in settings, return false
    if (!_settingsService.contextualRetrievalEnabled) return false;

    // Check device tier
    final capabilities = await _deviceService.getCapabilities();
    final recommendations = _recommendationService.getRecommendedModels(
      capabilities,
    );

    return recommendations.tier == DeviceTier.high ||
        recommendations.tier == DeviceTier.premium;
  }

  // For Gemma 2B (High tier): 4096 to 8192 tokens max depending on quantization
  // We'll be conservative.
  int get _modelMaxTokens {
    // Ideally fetch active model config, but for now use safe default
    // for on-device context generation
    return 2048;
  }

  /// Check if the document fits within context window for *one-shot* context
  bool canProcessFullDocument(int documentCharCount) {
    final availableChars = _calculateMaxDocumentChars(_modelMaxTokens);
    return documentCharCount <= availableChars;
  }

  int _calculateMaxDocumentChars(int modelMaxTokens) {
    final outputReserve = (modelMaxTokens * 0.25).floor();
    const promptOverhead = 150;
    const chunkReserve = 100;
    final available =
        modelMaxTokens - outputReserve - promptOverhead - chunkReserve;
    // ~4 chars per token heuristic
    return available * 4;
  }

  /// Generate context for a specific chunk using the document content
  Future<String> generateChunkContext({
    required String documentContent,
    required String chunk,
  }) async {
    final prompt =
        '''
<start_of_turn>user
Target chunk:
"$chunk"

Full Document Context:
"$documentContent"

Task:
Explain the context of the target chunk within the full document in 2-3 sentences. 
Does it refer to specific entities, dates, or concepts defined elsewhere? 
Make the explanation standalone so the chunk can be understood without the full document.
<end_of_turn>
<start_of_turn>model
''';

    try {
      final model = await FlutterGemma.getActiveModel();
      final chat = await model.createChat(temperature: 0.1);
      await chat.initSession();
      await chat.addQuery(Message(text: prompt, isUser: true));

      var response = '';
      await for (final token in chat.generateChatResponseAsync()) {
        if (token is TextResponse) {
          response += token.token;
        }
      }
      return response.trim();
    } on Exception catch (_) {
      // Fallback or log error
      return '';
    }
  }

  /// Batch process chunks to add context.
  /// Handles sliding windows for large documents.
  Future<List<ContextualizedChunk>> contextualizeDocument({
    required String documentContent,
    required List<String> chunks,
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <ContextualizedChunk>[];
    final maxChars = _calculateMaxDocumentChars(_modelMaxTokens);
    final useSlidingWindow = documentContent.length > maxChars;

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      var contextSource = documentContent;

      if (useSlidingWindow) {
        contextSource = _getRelevantWindow(documentContent, chunk, maxChars);
      }

      final context = await generateChunkContext(
        documentContent: contextSource,
        chunk: chunk,
      );

      results.add(
        ContextualizedChunk(
          originalContent: chunk,
          context: context,
          combinedContent: context.isNotEmpty ? '$context\n\n$chunk' : chunk,
        ),
      );

      onProgress?.call(i + 1, chunks.length);
    }

    return results;
  }

  String _getRelevantWindow(String fullDoc, String chunk, int maxChars) {
    final chunkStart = fullDoc.indexOf(chunk);
    if (chunkStart == -1) {
      return fullDoc.substring(0, min(fullDoc.length, maxChars));
    }

    final windowStart = max(0, chunkStart - maxChars ~/ 2);
    final windowEnd = min(fullDoc.length, windowStart + maxChars);
    return fullDoc.substring(windowStart, windowEnd);
  }
}
