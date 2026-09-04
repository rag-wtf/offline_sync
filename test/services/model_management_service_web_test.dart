import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  test(
    'accepts plugin-managed blob model paths without constructing a File',
    () async {
      expect(kIsWeb, isTrue);
      getAndRegisterMockRagSettingsService();
      final service = ModelManagementService(
        modelInstalledChecker: (filename) async =>
            filename == EmbeddingModels.gecko64.fileName,
        installedModelPathResolver: (_) async =>
            'blob:https://example.test/model-cache-entry',
      );
      addTearDown(() async {
        service.dispose();
        await unregisterTestHelpers();
      });

      await service.initialize();

      final gecko = service.models.firstWhere(
        (model) => model.id == EmbeddingModels.gecko64.id,
      );
      expect(gecko.status, ModelStatus.downloaded);
    },
    testOn: 'chrome',
  );
}
