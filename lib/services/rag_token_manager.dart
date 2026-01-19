/// Service for managing token estimation and budget calculations
class RagTokenManager {
  /// Estimates the number of tokens in a string
  /// Simplified estimation: roughly 4 characters per token
  int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
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
      if (limitedHistory.length >= 10) break;
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
