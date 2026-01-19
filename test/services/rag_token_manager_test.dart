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

      test('should return approx 1 token for 4 characters', () {
        expect(manager.estimateTokens('abcd'), equals(1));
      });

      test('should return 3 tokens for 10 characters', () {
        // (10/4).ceil() = 3
        expect(manager.estimateTokens('abcdefghij'), equals(3));
      });
    });

    group('buildHistoryWithBudget -', () {
      test('when budget is large enough, should return all history', () {
        final history = [
          'User: Hello',
          'Model: Hi there!',
        ];

        final result = manager.buildHistoryWithBudget(
          history,
          100,
        );

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
        final history = [
          'Message 1',
          'Message 2',
        ];

        // One message: "Message 2" -> 9 chars -> 3 tokens
        final result = manager.buildHistoryWithBudget(
          history,
          3,
        );

        expect(result, isNot(contains('Message 1')));
        expect(result, contains('Message 2'));
      });

      test('should handle empty history gracefully', () {
        expect(manager.buildHistoryWithBudget([], 100), isEmpty);
      });
    });
  });
}
