import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:offline_sync/services/model_config.dart';

typedef DigestHttpGet = Future<http.Response> Function(Uri uri);

class HuggingFaceDigestResolver {
  HuggingFaceDigestResolver({DigestHttpGet? get}) : _get = get ?? _getMetadata;

  static final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final DigestHttpGet _get;

  Future<String> resolve(ModelDefinition definition) async {
    final response = await _get(_metadataUri(definition.modelUrl)).timeout(
      const Duration(seconds: 15),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Hugging Face metadata request failed with HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Hugging Face metadata was not a file list');
    }

    for (final entry in decoded) {
      if (entry is! Map || entry['path'] != definition.fileName) continue;
      final lfs = entry['lfs'];
      final oid = lfs is Map ? lfs['oid'] : null;
      if (oid is String) {
        final digest = oid.startsWith('sha256:') ? oid.substring(7) : oid;
        if (_sha256Pattern.hasMatch(digest)) return digest.toLowerCase();
      }
      throw StateError(
        'Hugging Face metadata has no valid LFS digest for ${definition.id}',
      );
    }

    throw StateError(
      'Hugging Face metadata does not contain ${definition.fileName}',
    );
  }

  static Uri _metadataUri(String modelUrl) {
    final source = Uri.parse(modelUrl);
    final resolveIndex = source.pathSegments.indexOf('resolve');
    if (resolveIndex < 2) {
      throw FormatException(
        'Cannot derive a Hugging Face repository',
        modelUrl,
      );
    }

    final repository = source.pathSegments.sublist(0, resolveIndex);
    return Uri(
      scheme: source.scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      pathSegments: ['api', 'models', ...repository, 'tree', 'main'],
      queryParameters: const {'recursive': 'true'},
    );
  }

  static Future<http.Response> _getMetadata(Uri uri) {
    return http.get(uri, headers: const {'Accept': 'application/json'});
  }
}
