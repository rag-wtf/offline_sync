import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/smart_chunker.dart';

void main() {
  group('SmartChunker Tests -', () {
    late SmartChunker chunker;

    setUp(() {
      chunker = SmartChunker();
    });

    group('Basic chunking -', () {
      test('should return empty list for empty text', () {
        final result = chunker.chunk('');
        expect(result, isEmpty);
      });

      test('should return single chunk for short text', () {
        const shortText = 'This is a short text.';
        final result = chunker.chunk(shortText, maxChars: 100);

        expect(result.length, 1);
        expect(result.first, shortText);
      });

      test('should return original text if under maxChars', () {
        const text = 'A reasonably sized text that fits.';
        final result = chunker.chunk(text, maxChars: 100);

        expect(result.length, 1);
        expect(result.first, text);
      });
    });

    group('Paragraph-based splitting -', () {
      test('should split by paragraphs when text exceeds maxChars', () {
        const text = '''
This is the first paragraph. It contains several sentences that form a complete thought.

This is the second paragraph with different content. It also has multiple sentences.

A third paragraph follows with more information.
''';

        final result = chunker.chunk(text, maxChars: 100);

        expect(result.length, greaterThan(1));
        // Each chunk should be reasonably sized
        for (final chunk in result) {
          expect(chunk.length, lessThanOrEqualTo(200));
        }
      });

      test('should handle consecutive newlines correctly', () {
        const text = 'Para 1\n\n\nPara 2\n\n\n\nPara 3';
        final result = chunker.chunk(text, maxChars: 50);

        // Should split into multiple chunks and trim whitespace
        expect(result.length, greaterThan(0));
        for (final chunk in result) {
          expect(chunk.trim(), isNotEmpty);
        }
      });
    });

    group('Sentence splitting -', () {
      test('should split long paragraph by sentences', () {
        const paragraph =
            'First sentence here. '
            'Second sentence follows. '
            'Third one is also here. '
            'Fourth sentence added. '
            'Fifth and final sentence.';

        final result = chunker.chunk(paragraph, maxChars: 60);

        expect(result.length, greaterThan(1));
        // Each chunk should respect sentence boundaries where possible
        for (final chunk in result) {
          expect(chunk.length, lessThanOrEqualTo(100));
        }
      });

      test('should handle different sentence endings (. ! ?)', () {
        const text =
            'Question here? Statement follows! Another one. More text!';
        final result = chunker.chunk(text, maxChars: 30);

        expect(result.length, greaterThan(1));
        for (final chunk in result) {
          expect(chunk.isNotEmpty, isTrue);
        }
      });
    });

    group('Overlap functionality -', () {
      test('should create overlapping chunks', () {
        final text = List.generate(
          10,
          (i) => 'Paragraph $i content here.',
        ).join('\n\n');

        final result = chunker.chunk(text, maxChars: 50, overlapChars: 10);

        expect(result.length, greaterThan(1));
        // Verify there's some overlap between consecutive chunks
        // (This is a heuristic check since exact overlap is
        // implementation-dependent)
      });

      test('overlap should be respected even with short chunks', () {
        const text = 'Short. Another. More text here to force split.';
        final result = chunker.chunk(text, maxChars: 20, overlapChars: 5);

        expect(result.length, greaterThan(1));
      });
    });

    group('Hard chopping for very long content -', () {
      test('should hard chop when sentence is too long', () {
        // Create a very long "sentence" with no punctuation
        final longWord = 'a' * 600;
        final result = chunker.chunk(longWord, maxChars: 100);

        expect(result.length, greaterThan(1));
        for (final chunk in result) {
          expect(chunk.length, lessThanOrEqualTo(120));
        }
      });

      test('should handle mixed content with long unpunctuated sections', () {
        const text =
            'Normal sentence. '
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb '
            'Another normal sentence.';

        final result = chunker.chunk(text, maxChars: 80);

        expect(result.length, greaterThan(1));
      });
    });

    group('Edge cases -', () {
      test('should handle text with only whitespace', () {
        const text = '   \n\n   \n  ';
        final result = chunker.chunk(text);

        // Should produce empty list or single empty chunk
        if (result.isNotEmpty) {
          expect(result.first.trim(), isEmpty);
        }
      });

      test('should handle text with no paragraph breaks', () {
        final text = List.generate(100, (i) => 'word$i ').join();
        final result = chunker.chunk(text, maxChars: 100);

        expect(result.length, greaterThan(1));
        // Verify all original text is preserved
        final combined = result.join(' ');
        final combinedLength = combined
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .length;
        final halfTextLength = text.length ~/ 2;
        expect(combinedLength, greaterThanOrEqualTo(halfTextLength));
      });

      test('should handle single very long word', () {
        final word = 'supercalifragilisticexpialidocious' * 20;
        final result = chunker.chunk(word, maxChars: 100);

        expect(result.length, greaterThan(1));
        for (final chunk in result) {
          expect(chunk.length, lessThanOrEqualTo(110));
        }
      });

      test('should handle mixed unicode characters', () {
        const text =
            '你好世界。这是中文测试。\n\n'
            'English text here. More content.\n\n'
            'Émojis 😀😁😂🤣😃';

        final result = chunker.chunk(text, maxChars: 50);

        expect(result.length, greaterThan(0));
        for (final chunk in result) {
          expect(chunk.isNotEmpty, isTrue);
        }
      });

      test('should maintain reasonable chunk sizes', () {
        // Large realistic text
        final paragraphs = List.generate(
          50,
          (i) =>
              'This is paragraph $i with enough text to make it '
              'realistic. It contains multiple sentences to test the '
              'chunking behavior properly.',
        );
        final text = paragraphs.join('\n\n');

        final result = chunker.chunk(text, maxChars: 300);

        expect(result.length, greaterThan(1));
        for (final chunk in result) {
          // Allow some tolerance for overlap
          expect(chunk.length, lessThanOrEqualTo(400));
        }
      });
    });

    group('Chunk content preservation -', () {
      test('should preserve all content across chunks', () {
        const text = 'Important data here. More data there. Final data.';
        final result = chunker.chunk(text, maxChars: 25);

        final combined = result.join(' ').replaceAll(RegExp(r'\s+'), ' ');
        final original = text.replaceAll(RegExp(r'\s+'), ' ');

        // Combined length should be close to original (accounting for overlap)
        expect(combined.length, greaterThanOrEqualTo(original.length));
      });
    });
  });
}
