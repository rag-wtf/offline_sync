import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/models/document.dart';

void main() {
  group('Document.fromJson -', () {
    test('tolerates missing/null numeric and string fields', () {
      final doc = Document.fromJson(<String, dynamic>{
        'id': 'abc',
        'format': 'pdf',
        'ingested_at': 0,
      });

      expect(doc.id, 'abc');
      expect(doc.title, isNotNull);
      expect(doc.chunkCount, 0);
      expect(doc.totalCharacters, 0);
      expect(doc.contentHash, isNotNull);
    });
  });
}
