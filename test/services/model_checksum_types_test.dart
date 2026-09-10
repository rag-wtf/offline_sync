import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_checksum_types.dart';

void main() {
  test('ChecksumVerificationResult constructors work correctly', () {
    const v = ChecksumVerificationResult.verified();
    expect(v.status, ChecksumVerificationStatus.verified);
    expect(v.error, isNull);

    const m = ChecksumVerificationResult.mismatch();
    expect(m.status, ChecksumVerificationStatus.mismatch);
    expect(m.error, isNull);

    const e = ChecksumVerificationResult.readError('error');
    expect(e.status, ChecksumVerificationStatus.readError);
    expect(e.error, 'error');

    const custom = ChecksumVerificationResult(
      ChecksumVerificationStatus.verified,
    );
    expect(custom.status, ChecksumVerificationStatus.verified);
  });

  test('ChecksumFileMetadata stores properties', () {
    const meta = ChecksumFileMetadata(
      path: '/path/to/file',
      size: 1024,
      modifiedMillisecondsSinceEpoch: 123456789,
    );
    expect(meta.path, '/path/to/file');
    expect(meta.size, 1024);
    expect(meta.modifiedMillisecondsSinceEpoch, 123456789);
  });
}
