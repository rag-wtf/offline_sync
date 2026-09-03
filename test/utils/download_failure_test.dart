import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/utils/download_failure.dart';
import 'package:offline_sync/utils/hugging_face.dart';

void main() {
  const repo = 'https://huggingface.co/litert-community/Gemma3-1B-IT';

  group('DownloadFailure', () {
    test(
      'classifies typed 401/403 from flutter_gemma as gated access error',
      () {
        expect(
          isGatedAccessError(
            const DownloadException(DownloadError.unauthorized()),
          ),
          isTrue,
        );
        expect(
          isGatedAccessError(
            const DownloadException(DownloadError.forbidden()),
          ),
          isTrue,
        );
        expect(
          isGatedAccessError(
            const DownloadException(DownloadError.network('down')),
          ),
          isFalse,
        );
      },
    );

    test('classifies string errors with auth and gate status', () {
      expect(
        isGatedAccessError(
          Exception('HTTP 401 Unauthorized: Access to model is restricted'),
        ),
        isTrue,
      );
      expect(
        isGatedAccessError(Exception('403 Forbidden: GatedRepo access denied')),
        isTrue,
      );
      expect(
        isGatedAccessError(Exception('proxy returned 403 to the CDN')),
        isFalse,
      );
    });

    test('describeDownloadFailure provides 3-step advice for gated error', () {
      final message = describeDownloadFailure(
        const DownloadException(DownloadError.forbidden()),
        repoPage: repo,
      );
      expect(message, contains(repo));
      expect(message, contains('Check all three:'));
      expect(message, contains('accepted the licence on $repo'));
      expect(message, contains('token belongs to the same account'));
      expect(
        message,
        contains('Read access to the contents of all public gated repos'),
      );
    });

    test(
      'describeDownloadFailure passes through non-gated error verbatim',
      () {
        final message = describeDownloadFailure(
          Exception('disk full'),
          repoPage: repo,
        );
        expect(message, 'The download failed: Exception: disk full');
      },
    );

    test('does not classify advice text without auth status as gated', () {
      expect(isGatedAccessError('Hugging Face refused the download.'), isFalse);
    });

    group('deriveHuggingFaceRepoPage', () {
      test('derives repo URL from valid Hugging Face model URL', () {
        const modelUrl =
            'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/model.task';
        expect(deriveHuggingFaceRepoPage(modelUrl), repo);
      });

      test('returns original string when path has fewer than 2 segments', () {
        expect(
          deriveHuggingFaceRepoPage('https://huggingface.co/single-segment'),
          'https://huggingface.co/single-segment',
        );
      });

      test('returns original string for a non-Hugging Face URL', () {
        const url = 'https://example.com/owner/model/file.task';

        expect(deriveHuggingFaceRepoPage(url), url);
      });
    });
  });
}
