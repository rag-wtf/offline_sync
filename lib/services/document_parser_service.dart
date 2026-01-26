import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_plus/epub_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

enum DocumentFormat { pdf, docx, epub, markdown, plainText, unknown }

class ParsedDocument {
  const ParsedDocument({
    required this.title,
    required this.content,
    required this.format,
    required this.metadata,
    this.estimatedTokens = 0,
  });

  final String title;
  final String content;
  final DocumentFormat format;
  final Map<String, dynamic> metadata;
  final int estimatedTokens;
}

/// Service to parse various document formats into plain text
class DocumentParserService {
  /// Detect format from file name or path
  DocumentFormat detectFormat(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return DocumentFormat.pdf;
      case 'docx':
        return DocumentFormat.docx;
      case 'epub':
        return DocumentFormat.epub;
      case 'md':
      case 'markdown':
        return DocumentFormat.markdown;
      case 'txt':
      case 'json':
      case 'log':
        return DocumentFormat.plainText;
      default:
        return DocumentFormat.unknown;
    }
  }

  /// Parse document file and return structured content
  Future<ParsedDocument> parseDocument(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const FileSystemException('File not found');
    }
    final bytes = await file.readAsBytes();
    final fileName = filePath.split(Platform.pathSeparator).last;
    return parseDocumentFromBytes(bytes, fileName);
  }

  /// Parse document from bytes and return structured content
  Future<ParsedDocument> parseDocumentFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    final format = detectFormat(fileName);
    String content;
    final metadata = <String, dynamic>{
      'fileName': fileName,
      'fileSize': bytes.length,
      'extension': format.name,
    };

    switch (format) {
      case DocumentFormat.pdf:
        content = await _parsePdf(bytes);
      case DocumentFormat.docx:
        content = await _parseDocx(bytes);
      case DocumentFormat.epub:
        content = await _parseEpub(bytes);
      case DocumentFormat.markdown:
      case DocumentFormat.plainText:
        content = utf8.decode(bytes, allowMalformed: true);
      case DocumentFormat.unknown:
        // Try reading as text, fallback to error
        try {
          content = utf8.decode(bytes, allowMalformed: true);
          // If it looks binary (contains null bytes), abort
          if (content.contains('\u0000')) {
            throw Exception('Unsupported binary file format');
          }
        } on Exception catch (e) {
          throw Exception('Unsupported file format: $fileName ($e)');
        }
    }

    if (content.trim().isEmpty) {
      throw Exception('Document appears to be empty');
    }

    // Estimate tokens (simple 4 chars/token heuristic)
    final estimatedTokens = (content.length / 4).ceil();

    return ParsedDocument(
      title: fileName,
      content: content,
      format: format,
      metadata: metadata,
      estimatedTokens: estimatedTokens,
    );
  }

  Future<String> _parsePdf(Uint8List bytes) async {
    try {
      final document = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();
      return text;
    } catch (e) {
      throw Exception('Failed to parse PDF: $e');
    }
  }

  Future<String> _parseDocx(Uint8List bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // Verify it's a valid docx by checking for word/document.xml
      final documentEntry = archive.findFile('word/document.xml');
      if (documentEntry == null) {
        throw Exception('Invalid DOCX file: missing word/document.xml');
      }

      final content = String.fromCharCodes(documentEntry.content as List<int>);
      final document = XmlDocument.parse(content);

      // Extract text from <w:t> tags
      final buffer = StringBuffer();
      // Find all paragraphs <w:p>
      for (final paragraph in document.findAllElements('w:p')) {
        final paragraphText = paragraph
            .findAllElements('w:t')
            .map((node) => node.innerText)
            .join();

        if (paragraphText.isNotEmpty) {
          buffer.writeln(paragraphText);
        }
      }

      return buffer.toString();
    } catch (e) {
      throw Exception('Failed to parse DOCX: $e');
    }
  }

  Future<String> _parseEpub(Uint8List bytes) async {
    try {
      final epubBook = await EpubReader.readBook(bytes);

      final buffer = StringBuffer();

      // Extract title/author if available
      // Helper to strip HTML tags
      String stripHtml(String html) {
        return html.replaceAll(
          RegExp('<[^>]*>', multiLine: true, caseSensitive: false),
          ' ',
        );
      }

      // Iterate over chapters
      for (final chapter in epubBook.chapters) {
        if (chapter.htmlContent != null) {
          buffer.writeln(stripHtml(chapter.htmlContent!));
        }

        // Handle nested sub-chapters
        for (final subChapter in chapter.subChapters) {
          if (subChapter.htmlContent != null) {
            buffer.writeln(stripHtml(subChapter.htmlContent!));
          }
        }
      }

      return buffer.toString();
    } catch (e) {
      throw Exception('Failed to parse EPUB: $e');
    }
  }
}
