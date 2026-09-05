import 'package:offline_sync/services/rag_constants.dart';

/// Service for managing token estimation and budget calculations
class RagTokenManager {
  RagTokenManager({this.tokenCounter});

  /// Optional tokenizer supplied by a live inference session.
  final Future<int> Function(String text)? tokenCounter;

  /// Estimates the number of tokens in a string
  /// Conservative fallback for prompt budgeting when no session tokenizer is
  /// available. Three Unicode code points per token avoids the old optimistic
  /// chars/4 estimate for code, CJK, and punctuation-heavy text.
  int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.runes.length / 3).ceil();
  }

  /// Counts tokens with the active session tokenizer when one is available.
  Future<int> countTokens(
    String text, {
    Future<int> Function(String text)? exactCounter,
  }) async {
    final counter = exactCounter ?? tokenCounter;
    if (counter != null) {
      try {
        return await counter(text);
      } on Object catch (_) {
        // Fall back to a conservative estimate if the runtime tokenizer fails.
      }
    }
    return estimateTokens(text);
  }

  /// Builds a conversation history that fits within the token budget
  /// Always includes the most recent exchanges
  String buildHistoryWithBudget(List<String> history, int tokenBudget) {
    if (history.isEmpty) return '';

    // Start with the most recent message if it fits the budget
    final limitedHistory = <String>[];
    var currentTokens = 0;

    for (var i = history.length - 1; i >= 0; i--) {
      final msg = history[i];
      final msgTokens = estimateTokens(msg);

      // Always include most recent message, even if it exceeds budget,
      // as long as it's the very first one we're adding.
      // Otherwise, stay within budget.
      if (limitedHistory.isEmpty || currentTokens + msgTokens <= tokenBudget) {
        limitedHistory.insert(0, msg);
        currentTokens += msgTokens;

        // If we only have one message and it already exceeds budget, stop.
        if (currentTokens > tokenBudget) break;
      } else {
        break; // Budget exceeded
      }

      // Stop if we have a reasonable amount of context (e.g., max 10 messages)
      // to avoid extremely long loops, though tokenBudget usually handles this.
      if (limitedHistory.length >= RagConstants.historyBuildMessageCap) break;
    }

    if (limitedHistory.isEmpty) return '';

    return '''
Previous conversation:
${limitedHistory.join('\n')}

''';
  }

  /// Calculates the best chunk size and overlap for a given document
  int calculateChunkOverlap(int chunkSize, double ratio) {
    return (chunkSize * ratio).floor();
  }
}
