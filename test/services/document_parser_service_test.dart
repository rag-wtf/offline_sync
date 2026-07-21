import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

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

      test(
        'parses unknown text-like files as text while preserving metadata',
        () async {
          const content = 'mystery format content';
          final result = await service.parseDocumentFromBytes(
            Uint8List.fromList(utf8.encode(content)),
            'notes.custom',
          );

          expect(result.content, content);
          expect(result.format, DocumentFormat.unknown);
          expect(
            result.metadata,
            containsPair('fileName', 'notes.custom'),
          );
          expect(result.metadata, containsPair('fileSize', content.length));
          expect(result.metadata, containsPair('extension', 'unknown'));
        },
      );

      test(
        'rejects binary unknown files instead of treating them as text',
        () async {
          await expectLater(
            () => service.parseDocumentFromBytes(
              Uint8List.fromList(const [0, 159, 146, 150]),
              'archive.bin',
            ),
            throwsA(
              isA<Exception>().having(
                (error) => error.toString(),
                'message',
                contains('Unsupported file format: archive.bin'),
              ),
            ),
          );
        },
      );

      test('parses non-ASCII DOCX text without corruption', () async {
        const text = 'Café — 日本語 — 😀 — “smart quotes”';
        final documentXml = [
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
          '<w:body><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:body></w:document>',
        ].join();
        final documentBytes = utf8.encode(documentXml);
        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'word/document.xml',
              documentBytes.length,
              documentBytes,
            ),
          );
        final encoded = ZipEncoder().encode(archive);
        expect(encoded, isNotNull);

        final parsed = await service.parseDocumentFromBytes(
          Uint8List.fromList(encoded),
          'sample.docx',
        );

        expect(parsed.content, contains('Café'));
        expect(parsed.content, contains('日本語'));
        expect(parsed.content, contains('😀'));
        expect(parsed.content, contains('“smart quotes”'));
      });

      test(
        'throws a helpful error when DOCX bytes lack document.xml',
        () async {
          final archive = Archive()
            ..addFile(
              ArchiveFile(
                'word/styles.xml',
                8,
                utf8.encode('<styles/>'),
              ),
            );
          final encoded = ZipEncoder().encode(archive);

          await expectLater(
            () => service.parseDocumentFromBytes(
              Uint8List.fromList(encoded),
              'broken.docx',
            ),
            throwsA(
              isA<Exception>().having(
                (error) => error.toString(),
                'message',
                contains('Invalid DOCX file: missing word/document.xml'),
              ),
            ),
          );
        },
      );

      test('wraps PDF parser failures with PDF-specific context', () async {
        await expectLater(
          () => service.parseDocumentFromBytes(
            Uint8List.fromList(const [1, 2, 3, 4]),
            'broken.pdf',
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('Failed to parse PDF:'),
            ),
          ),
        );
      });

      test('parses text from a valid PDF', () async {
        final pdf = PdfDocument();
        pdf.pages.add().graphics.drawString(
          'PDF content',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
        final bytes = pdf.saveSync();
        pdf.dispose();

        final parsed = await service.parseDocumentFromBytes(
          Uint8List.fromList(bytes),
          'valid.pdf',
        );

        expect(parsed.content, contains('PDF content'));
        expect(parsed.format, DocumentFormat.pdf);
      });

      test('parses EPUB chapters and strips markup and entities', () async {
        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'META-INF/container.xml',
              _containerXml.length,
              utf8.encode(_containerXml),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/content.opf',
              _contentOpf.length,
              utf8.encode(_contentOpf),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/nav.xhtml',
              _navXhtml.length,
              utf8.encode(_navXhtml),
            ),
          )
          ..addFile(
            ArchiveFile(
              'OEBPS/chapter.xhtml',
              _chapterXhtml.length,
              utf8.encode(_chapterXhtml),
            ),
          );

        final encoded = ZipEncoder().encode(archive);
        final parsed = await service.parseDocumentFromBytes(
          Uint8List.fromList(encoded),
          'book.epub',
        );

        expect(parsed.content, contains('Chapter text & more'));
        expect(parsed.content, isNot(contains('<p>')));
        expect(parsed.content, isNot(contains('hidden')));
        expect(parsed.format, DocumentFormat.epub);
      });

      test('wraps invalid EPUB bytes with EPUB-specific context', () async {
        await expectLater(
          () => service.parseDocumentFromBytes(
            Uint8List.fromList(const [1, 2, 3]),
            'broken.epub',
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('Failed to parse EPUB:'),
            ),
          ),
        );
      });
    });
  });
}

const _containerXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';

const _contentOpf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:identifier id="BookId">book-id</dc:identifier>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="chapter"/></spine>
</package>
''';

const _navXhtml = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Navigation</title></head>
  <body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">Chapter</a></li></ol></nav></body>
</html>
''';

const _chapterXhtml = '''
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><style>.hidden { display: none; }</style></head>
  <body><p>Chapter text &amp; more</p><script>hidden</script></body>
</html>
''';
