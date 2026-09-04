enum ChecksumVerificationStatus { verified, mismatch, readError }

class ChecksumVerificationResult {
  const ChecksumVerificationResult(this.status, [this.error]);

  const ChecksumVerificationResult.verified()
    : status = ChecksumVerificationStatus.verified,
      error = null;

  const ChecksumVerificationResult.mismatch()
    : status = ChecksumVerificationStatus.mismatch,
      error = null;

  const ChecksumVerificationResult.readError(this.error)
    : status = ChecksumVerificationStatus.readError;

  final ChecksumVerificationStatus status;
  final Object? error;
}

class ChecksumFileMetadata {
  const ChecksumFileMetadata({
    required this.path,
    required this.size,
    required this.modifiedMillisecondsSinceEpoch,
  });

  final String path;
  final int size;
  final int modifiedMillisecondsSinceEpoch;
}
