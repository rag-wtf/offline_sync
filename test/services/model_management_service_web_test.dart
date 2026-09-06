import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  test(
    'accepts plugin-managed blob and OPFS paths without constructing a File',
    () async {
      getAndRegisterMockRagSettingsService();
      addTearDown(() async {
        await unregisterTestHelpers();
      });

      for (final pluginPath in [
        'blob:https://example.test/model-cache-entry',
        'opfs://models/gecko-64',
      ]) {
        final service = ModelManagementService(
          isWebOverride: true,
          embeddingModelActivator: (_) async {},
          modelInstalledChecker: (filename) async =>
              filename == EmbeddingModels.gecko64.fileName,
          installedModelPathResolver: (_) async => pluginPath,
          fileChecksumVerifier: (_, _) async {
            throw StateError('web plugin paths must not reach File');
          },
        );
        addTearDown(service.dispose);

        await service.initialize();

        final gecko = service.models.firstWhere(
          (model) => model.id == EmbeddingModels.gecko64.id,
        );
        expect(gecko.status, ModelStatus.downloaded);
      }
    },
  );
}
