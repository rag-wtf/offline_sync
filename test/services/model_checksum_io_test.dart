import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_checksum_io.dart';
import 'package:offline_sync/services/model_checksum_types.dart';

void main() {
  test(
    'reads metadata and verifies, rejects, and deletes checksum files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'checksum_io_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/model.bin');
      await file.writeAsBytes([1, 2, 3, 4]);
      final expected = sha256.convert([1, 2, 3, 4]).toString();

      final metadata = await readChecksumFileMetadata(file);
      expect(metadata?.path, file.path);
      expect(metadata?.size, 4);
      expect(
        (await verifyChecksumFile(file, expected)).status,
        ChecksumVerificationStatus.verified,
      );
      expect(
        (await verifyChecksumFile(file, 'wrong')).status,
        ChecksumVerificationStatus.mismatch,
      );

      final missing = File('${directory.path}/missing.bin');
      expect(await readChecksumFileMetadata(missing), isNull);
      expect(
        (await verifyChecksumFile(missing, expected)).status,
        ChecksumVerificationStatus.readError,
      );
      await deleteChecksumFile(file);
      expect(file.existsSync(), isFalse);
    },
  );
}
