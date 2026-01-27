import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/document_parser_service.dart';

void main() {
  group('DocumentParserServiceTest -', () {
    late DocumentParserService service;

    setUp(() {
      service = DocumentParserService();
    });

    group('detectFormat -', () {
      test('should detect PDF', () {
        expect(service.detectFormat('test.pdf'), DocumentFormat.pdf);
        expect(service.detectFormat('/path/to/FILE.PDF'), DocumentFormat.pdf);
      });

      test('should detect DOCX', () {
        expect(service.detectFormat('test.docx'), DocumentFormat.docx);
      });

      test('should detect EPUB', () {
        expect(service.detectFormat('book.epub'), DocumentFormat.epub);
      });

      test('should detect Markdown', () {
        expect(service.detectFormat('readme.md'), DocumentFormat.markdown);
        expect(service.detectFormat('notes.markdown'), DocumentFormat.markdown);
      });

      test('should detect Plain Text', () {
        expect(service.detectFormat('log.txt'), DocumentFormat.plainText);
        expect(service.detectFormat('data.json'), DocumentFormat.plainText);
        expect(service.detectFormat('error.log'), DocumentFormat.plainText);
      });

      test('should return unknown for unsupported extensions', () {
        expect(service.detectFormat('image.png'), DocumentFormat.unknown);
        expect(service.detectFormat('app.exe'), DocumentFormat.unknown);
      });
    });

    group('parseDocument -', () {
      test('should throw FileSystemException if file does not exist', () async {
        await expectLater(
          () => service.parseDocument('non_existent_file.txt'),
          throwsA(isA<FileSystemException>()),
        );
      });

      // Note: Actual parsing tests for PDF/DOCX/EPUB are hard to unit test
      // without real files or extensive mocking of the underlying libraries.
      // We will focus on integration tests or manual verification for those.
      // Here, we can test plain text parsing if we create a temp file.

      test('should parse plain text file correctly', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final file = File('${tempDir.path}/test.txt');
        await file.writeAsString('Hello World');

        final result = await service.parseDocument(file.path);

        expect(result.content, 'Hello World');
        expect(result.format, DocumentFormat.plainText);
        expect(result.title, 'test.txt');
        expect(result.estimatedTokens, 3); // ceil(11/4) = 3

        // Cleanup
        await tempDir.delete(recursive: true);
      });

      test('should throw exception for empty file', () async {
        final tempDir = Directory.systemTemp.createTempSync();
        final file = File('${tempDir.path}/empty.txt');
        await file.writeAsString('   \n  ');

        await expectLater(
          () => service.parseDocument(file.path),
          throwsException,
        );

        // Cleanup
        await tempDir.delete(recursive: true);
      });
    });

    group('parseDocumentFromBytes -', () {
      test('should parse plain text bytes correctly', () async {
        const content = 'Hello Bytes';
        final bytes = utf8.encode(content);
        final result = await service.parseDocumentFromBytes(
          Uint8List.fromList(bytes),
          'test.txt',
        );

        expect(result.content, content);
        expect(result.format, DocumentFormat.plainText);
        expect(result.title, 'test.txt');
        expect(result.estimatedTokens, 3);
      });
    });
  });
}
