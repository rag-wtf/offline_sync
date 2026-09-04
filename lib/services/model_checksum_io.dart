import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:offline_sync/services/model_checksum_types.dart';

typedef ChecksumFile = File;

ChecksumFile createChecksumFile(String path) => File(path);

Future<ChecksumFileMetadata?> readChecksumFileMetadata(
  ChecksumFile file,
) async {
  try {
    if (!file.existsSync()) return null;
    final stat = file.statSync();
    return ChecksumFileMetadata(
      path: file.path,
      size: stat.size,
      modifiedMillisecondsSinceEpoch: stat.modified.millisecondsSinceEpoch,
    );
  } on Object {
    return null;
  }
}

Future<ChecksumVerificationResult> verifyChecksumFile(
  ChecksumFile file,
  String expectedSha256,
) async {
  try {
    final metadata = await readChecksumFileMetadata(file);
    if (metadata == null) {
      return const ChecksumVerificationResult.readError('file is not readable');
    }
    final actualSha256 = await compute(_sha256ForPath, file.path);
    if (actualSha256 == expectedSha256.toLowerCase()) {
      return const ChecksumVerificationResult.verified();
    }
    return const ChecksumVerificationResult.mismatch();
  } on Object catch (error) {
    return ChecksumVerificationResult.readError(error);
  }
}

Future<String> _sha256ForPath(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

Future<void> deleteChecksumFile(ChecksumFile file) async {
  await file.delete();
}
