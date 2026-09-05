import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/rag_token_manager.dart';

void main() {
  group('RagTokenManager -', () {
    late RagTokenManager manager;

    setUp(() {
      manager = RagTokenManager();
    });

    group('estimateTokens -', () {
      test('should return 0 for empty string', () {
        expect(manager.estimateTokens(''), equals(0));
      });

      test('should use a conservative three-code-point fallback', () {
        expect(manager.estimateTokens('abcd'), equals(2));
      });

      test('should count Unicode code points for fallback budgeting', () {
        expect(manager.estimateTokens('abcdefghij'), equals(4));
      });

      test('uses an exact session tokenizer when available', () async {
        final count = await manager.countTokens(
          'prompt',
          exactCounter: (text) async {
            expect(text, 'prompt');
            return 17;
          },
        );

        expect(count, 17);
      });
    });

    group('buildHistoryWithBudget -', () {
      test('when budget is large enough, should return all history', () {
        final history = ['User: Hello', 'Model: Hi there!'];

        final result = manager.buildHistoryWithBudget(history, 100);

        expect(result, contains('User: Hello'));
        expect(result, contains('Model: Hi there!'));
      });

      test('when budget is small, should truncate history from oldest', () {
        final history = [
          'Message 1', // Oldest
          'Message 2',
          'Message 3', // Newest
        ];

        // Last 2 messages: "Message 2\nMessage 3" (approx 6 tokens)
        final result = manager.buildHistoryWithBudget(
          history,
          6, // Enough for last 2
        );

        expect(result, isNot(contains('Message 1')));
        expect(result, contains('Message 2'));
        expect(result, contains('Message 3'));
      });

      test('when budget is extremely small, should stay within budget', () {
        final history = ['Message 1', 'Message 2'];

        // One message: "Message 2" -> 9 chars -> 3 tokens
        final result = manager.buildHistoryWithBudget(history, 3);

        expect(result, isNot(contains('Message 1')));
        expect(result, contains('Message 2'));
      });

      test('should handle empty history gracefully', () {
        expect(manager.buildHistoryWithBudget([], 100), isEmpty);
      });

      test('drops the newest message when it alone exceeds budget', () {
        final result = manager.buildHistoryWithBudget([
          'old',
          'this newest message is definitely too long',
        ], 1);

        expect(
          result,
          isNot(contains('this newest message is definitely too long')),
        );
        expect(result, contains('old'));
      });

      test('fits the complete prompt after exact token counting', () async {
        final prompt = await manager.buildPromptWithinBudget(
          query: 'question',
          history: const [
            'old history that should be removed',
            'new history',
          ],
          context: const [
            'first context',
            'second context that should be removed',
          ],
          maxTokens: 370,
          countTokens: (text) async => text.runes.length,
        );

        expect(prompt.runes.length, lessThanOrEqualTo(370));
        expect(prompt, isNot(contains('old history')));
        expect(prompt, isNot(contains('second context')));
        expect(prompt, isNot(contains('new history')));
        expect(prompt, contains('question'));
      });

      test('caps returned history to the most recent ten messages', () {
        final history = List.generate(12, (index) => 'Message $index');

        final result = manager.buildHistoryWithBudget(history, 1000);
        final returnedLines = result
            .split('\n')
            .where((line) => line.startsWith('Message '))
            .toList();

        expect(returnedLines, hasLength(10));
        expect(returnedLines, isNot(contains('Message 0')));
        expect(returnedLines, isNot(contains('Message 1')));
        expect(returnedLines.first, 'Message 2');
        expect(returnedLines.last, 'Message 11');
      });
    });

    group('calculateChunkOverlap -', () {
      test('floors the overlap ratio against chunk size', () {
        expect(manager.calculateChunkOverlap(101, 0.25), 25);
      });
    });
  });
}
