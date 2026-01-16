import 'dart:math';

/// Intelligent text chunker that respects document structure
class SmartChunker {
  /// Split text into chunks respecting structure
  /// (headers, paragraphs, sentences)
  ///
  /// [text] The full document text
  /// [maxChars] Maximum characters per chunk (soft limit)
  /// [overlapChars] Number of characters to overlap between chunks
  List<String> chunk(
    String text, {
    int maxChars = 1000,
    int overlapChars = 100,
  }) {
    if (text.isEmpty) return [];
    if (text.length <= maxChars) return [text];

    final chunks = <String>[];

    // 1. Split by major sections (Markdown headers)
    // Regex splits but keeps delimiters? No, split usually consumes.
    // We'll traverse manually or split by newlines and reconstruct.

    // Simple approach: Split by double newlines (paragraphs) first
    // If a paragraph is too large, split by sentences
    // If a sentence is too large, split by words/chars

    final paragraphs = text.split(RegExp(r'\n\s*\n'));

    final currentChunk = StringBuffer();

    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      if (paragraph.isEmpty) continue;

      // Check if adding this paragraph exceeds maxChars
      if (currentChunk.length + paragraph.length + 2 > maxChars) {
        // If current chunk is not empty, finalize it
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.toString().trim());

          // Prepare next chunk with overlap
          // Get the last N chars from current chunk for overlap
          final overlapText = _getOverlap(
            currentChunk.toString(),
            overlapChars,
          );
          currentChunk.clear();
          if (overlapText.isNotEmpty) {
            currentChunk.write('$overlapText\n\n');
          }
        }

        // If the paragraph ITSELF is larger than maxChars, we need to split it
        if (paragraph.length > maxChars) {
          // If we have overlap from previous, add it to the first sub-chunk?
          // The buffer currently contains overlap (if any).

          final subChunks = _splitLargeParagraph(
            paragraph,
            maxChars - currentChunk.length,
            maxChars,
            overlapChars,
          );

          // Add all subchunks except the last one to the list
          for (var j = 0; j < subChunks.length - 1; j++) {
            // Prepend current buffer (overlap) to first subchunk if it exists
            if (j == 0 && currentChunk.isNotEmpty) {
              chunks.add((currentChunk.toString() + subChunks[j]).trim());
              currentChunk.clear();
            } else {
              chunks.add(subChunks[j]);
            }
          }

          // The last sub-chunk becomes the start of our next accumulation
          if (subChunks.isNotEmpty) {
            if (currentChunk.isNotEmpty && subChunks.length == 1) {
              // Only one subchunk that fit with the overlap?
              // Logic ensures _split returns chunks <= maxChars
              currentChunk.write(subChunks.last);
            } else {
              currentChunk.write(subChunks.last);
            }
          }
        } else {
          // Paragraph fits in a new chunk (plus overlap)
          currentChunk.write(paragraph);
        }
      } else {
        // Safe to add paragraph to current chunk
        if (currentChunk.isNotEmpty) {
          currentChunk.write('\n\n');
        }
        currentChunk.write(paragraph);
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
    }

    return chunks;
  }

  /// Split a large paragraph into smaller chunks by sentence/punctuation
  List<String> _splitLargeParagraph(
    String paragraph,
    int firstChunkLimit,
    int maxChars,
    int overlapChars,
  ) {
    final chunks = <String>[];

    // Split by sentence endings (. ! ? followed by space or newline)
    // Using positive lookbehind to keep the punctuation is hard in
    // Dart Regexp split
    // So we'll replace with a specialized delimiter
    final sentences = paragraph
        .replaceAllMapped(
          RegExp(r'([.!?])\s+'),
          (match) => '${match.group(1)}|<SPLIT>|',
        )
        .split('|<SPLIT>|');

    final currentBuffer = StringBuffer();
    // The limit for the *current* accumulating chunk.
    // Starts with firstChunkLimit, then resets to maxChars.
    var currentLimit = firstChunkLimit > 100 ? firstChunkLimit : maxChars;

    for (final sentence in sentences) {
      if (sentence.trim().isEmpty) continue;

      if (currentBuffer.length + sentence.length + 1 > currentLimit) {
        if (currentBuffer.isNotEmpty) {
          chunks.add(currentBuffer.toString().trim());

          final overlap = _getOverlap(currentBuffer.toString(), overlapChars);
          currentBuffer
            ..clear()
            ..write('$overlap ');
          currentLimit = maxChars; // Reset limit for subsequent chunks
        }

        // If sentence itself is huge (no punctuation), hard chop it
        if (sentence.length > maxChars) {
          final chopped = _hardChop(sentence, maxChars, overlapChars);
          // Add all chop parts
          if (currentBuffer.isNotEmpty) {
            // Prepend overlap to first chop?
            // Ideally yes, but tricky. Let's simplfy:
            // Add current buffer as is, restart.
            // Actually, loops handle this.
            chunks.add(currentBuffer.toString().trim());
            currentBuffer.clear();
          }

          chunks.addAll(chopped.sublist(0, chopped.length - 1));
          currentBuffer.write(chopped.last);
        } else {
          if (currentBuffer.isNotEmpty) currentBuffer.write(' ');
          currentBuffer.write(sentence);
        }
      } else {
        if (currentBuffer.isNotEmpty) currentBuffer.write(' ');
        currentBuffer.write(sentence);
      }
    }

    if (currentBuffer.isNotEmpty) {
      chunks.add(currentBuffer.toString().trim());
    }

    return chunks;
  }

  String _getOverlap(String text, int overlapChars) {
    if (text.length <= overlapChars) return text;
    // Try to cut at space
    final substr = text.substring(text.length - overlapChars);
    final firstSpace = substr.indexOf(' ');
    if (firstSpace != -1 && firstSpace < substr.length - 1) {
      // Return from first space to end to avoid cutting words
      return substr.substring(firstSpace + 1);
    }
    return substr;
  }

  List<String> _hardChop(String text, int maxChars, int overlapChars) {
    final chunks = <String>[];
    for (var i = 0; i < text.length; i += maxChars - overlapChars) {
      final end = min(i + maxChars, text.length);
      chunks.add(text.substring(i, end));
    }
    return chunks;
  }
}
