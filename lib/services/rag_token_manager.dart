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
    final limitedHistory = selectHistoryWithBudget(history, tokenBudget);

    if (limitedHistory.isEmpty) return '';

    return '''
Previous conversation:
${limitedHistory.join('\n')}

''';
  }

  /// Selects recent history without ever forcing one oversized message into
  /// the prompt. An oversized recent message is skipped so an older, smaller
  /// message can still be useful.
  List<String> selectHistoryWithBudget(List<String> history, int tokenBudget) {
    if (history.isEmpty || tokenBudget <= 0) return [];

    final limitedHistory = <String>[];
    var currentTokens = 0;
    for (
      var i = history.length - 1;
      i >= 0 && limitedHistory.length < RagConstants.historyBuildMessageCap;
      i--
    ) {
      final message = history[i];
      final messageTokens = estimateTokens(message);
      if (messageTokens == 0 || currentTokens + messageTokens > tokenBudget) {
        continue;
      }
      limitedHistory.insert(0, message);
      currentTokens += messageTokens;
    }
    return limitedHistory;
  }

  /// Builds the final generation prompt and verifies it with the active
  /// tokenizer. History is discarded oldest-first, then context is discarded
  /// lowest-priority-first, until the complete prompt fits the model limit.
  Future<String> buildPromptWithinBudget({
    required String query,
    required List<String> history,
    required List<String> context,
    required int maxTokens,
    required Future<int> Function(String text) countTokens,
  }) async {
    final historyBudget = (maxTokens * RagConstants.historyBudgetRatio).floor();
    final contextBudget = (maxTokens * RagConstants.contextBudgetRatio).floor();
    final selectedHistory = selectHistoryWithBudget(history, historyBudget);
    final selectedContext = <String>[];
    var contextTokens = 0;
    for (var i = 0; i < context.length; i++) {
      final formatted = '[Source ${i + 1}]: ${context[i]}';
      final tokens = estimateTokens(formatted);
      if (contextTokens + tokens > contextBudget) break;
      selectedContext.add(formatted);
      contextTokens += tokens;
    }

    while (true) {
      final prompt = _formatPrompt(
        query: query,
        history: selectedHistory,
        context: selectedContext,
      );
      if (await countTokens(prompt) <= maxTokens) return prompt;

      if (selectedHistory.isNotEmpty) {
        selectedHistory.removeAt(0);
        continue;
      }
      if (selectedContext.isNotEmpty) {
        selectedContext.removeLast();
        continue;
      }

      final minimalPrompt = _formatPrompt(
        query: '',
        history: const [],
        context: const [],
      );
      if (await countTokens(minimalPrompt) > maxTokens) {
        throw StateError('Prompt instructions exceed the model context limit');
      }

      var low = 0;
      var high = query.runes.length;
      var best = '';
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        final candidate = _takeRunes(query, middle);
        final candidatePrompt = _formatPrompt(
          query: candidate,
          history: const [],
          context: const [],
        );
        if (await countTokens(candidatePrompt) <= maxTokens) {
          best = candidate;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      return _formatPrompt(query: best, history: const [], context: const []);
    }
  }

  String _formatPrompt({
    required String query,
    required List<String> history,
    required List<String> context,
  }) {
    final historySection = history.isEmpty
        ? ''
        : 'Previous conversation:\n${history.join('\n')}\n\n';
    final contextSection = context.isEmpty
        ? 'No relevant context found.'
        : context.join('\n\n');
    return '''
${historySection}Context:
$contextSection

Question: $query

Instructions:
- Answer the question accurately and concisely based on the context above.
- If the context does not contain relevant information to answer the question, say "I don't have enough information."
- Do not append disclaimer phrases or repeat instructions after answering.''';
  }

  String _takeRunes(String text, int count) =>
      String.fromCharCodes(text.runes.take(count));

  /// Calculates the best chunk size and overlap for a given document
  int calculateChunkOverlap(int chunkSize, double ratio) {
    return (chunkSize * ratio).floor();
  }
}
