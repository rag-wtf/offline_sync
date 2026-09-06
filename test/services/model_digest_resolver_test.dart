import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_digest_resolver.dart';

void main() {
  test('reads the current LFS SHA-256 from Hugging Face metadata', () async {
    Uri? requestedUri;
    final resolver = HuggingFaceDigestResolver(
      get: (uri) async {
        requestedUri = uri;
        return http.Response(
          jsonEncode([
            {
              'path': InferenceModels.gemma3n_2B.fileName,
              'lfs': {
                'oid':
                    'sha256:ABCDEF0123456789ABCDEF0123456789'
                    'ABCDEF0123456789ABCDEF0123456789',
              },
            },
          ]),
          200,
        );
      },
    );

    final digest = await resolver.resolve(InferenceModels.gemma3n_2B);

    expect(
      requestedUri.toString(),
      'https://huggingface.co/api/models/google/gemma-3n-E2B-it-litert-preview/'
      'tree/main?recursive=true',
    );
    expect(
      digest,
      'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
    );
  });

  test('rejects a metadata response without the requested LFS file', () async {
    final resolver = HuggingFaceDigestResolver(
      get: (_) async => http.Response('[]', 200),
    );

    expect(
      () => resolver.resolve(InferenceModels.gemma3n_2B),
      throwsA(isA<StateError>()),
    );
  });
}
