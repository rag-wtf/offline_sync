import 'package:offline_sync/services/model_checksum_types.dart';

typedef ChecksumFile = Object;

ChecksumFile createChecksumFile(String path) => path;

Future<ChecksumFileMetadata?> readChecksumFileMetadata(
  ChecksumFile file,
) async => null;

Future<ChecksumVerificationResult> verifyChecksumFile(
  ChecksumFile file,
  String expectedSha256,
) async => const ChecksumVerificationResult.readError(
  'native file verification is unavailable on web',
);

Future<void> deleteChecksumFile(ChecksumFile file) async {}
