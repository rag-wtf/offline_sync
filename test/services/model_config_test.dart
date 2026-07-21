import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_config.dart';

void main() {
  group('ModelConfig', () {
    test('allModels combines inference and embedding catalogs', () {
      final allModels = ModelConfig.allModels;

      expect(
        allModels.map((model) => model.id),
        containsAll(<String>[
          InferenceModels.gemma3_270M.id,
          InferenceModels.gemma3_1B.id,
          InferenceModels.gemma3n_2B.id,
          InferenceModels.gemma3n_4B.id,
          EmbeddingModels.gecko64.id,
          EmbeddingModels.embeddingGemma256.id,
          EmbeddingModels.embeddingGemma512.id,
          EmbeddingModels.embeddingGemma1024.id,
        ]),
      );
    });

    test('activeInferenceModelOrDefault returns matching configured model', () {
      final model = ModelConfig.activeInferenceModelOrDefault('gemma3n-e2b');

      expect(model, same(InferenceModels.gemma3n_2B));
    });

    test('activeInferenceModelOrDefault falls back for null or unknown ids', () {
      expect(
        ModelConfig.activeInferenceModelOrDefault(null),
        same(InferenceModels.gemma3_270M),
      );
      expect(
        ModelConfig.activeInferenceModelOrDefault('missing-model'),
        same(InferenceModels.gemma3_270M),
      );
    });
  });

  group('ModelDefinition', () {
    test('fileName extracts the trailing path segment', () {
      expect(
        EmbeddingModels.gecko64.fileName,
        'Gecko_64_quant.tflite',
      );
    });

    test('sizeFormatted renders KB, MB, and GB thresholds', () {
      const kbModel = ModelDefinition(
        id: 'kb',
        name: 'KB',
        modelUrl: 'https://example.com/models/kb.bin',
        type: AppModelType.embedding,
        sizeBytes: 700 * 1024,
        minRamMB: 1,
        requiresGpu: false,
        tier: DeviceTier.low,
        maxTokens: 1,
      );
      const mbModel = ModelDefinition(
        id: 'mb',
        name: 'MB',
        modelUrl: 'https://example.com/models/mb.bin',
        type: AppModelType.embedding,
        sizeBytes: 179 * 1024 * 1024,
        minRamMB: 1,
        requiresGpu: false,
        tier: DeviceTier.low,
        maxTokens: 1,
      );
      const gbModel = ModelDefinition(
        id: 'gb',
        name: 'GB',
        modelUrl: 'https://example.com/models/gb.bin',
        type: AppModelType.embedding,
        sizeBytes: 3 * 1024 * 1024 * 1024,
        minRamMB: 1,
        requiresGpu: false,
        tier: DeviceTier.low,
        maxTokens: 1,
      );

      expect(kbModel.sizeFormatted, '700KB');
      expect(mbModel.sizeFormatted, '179MB');
      expect(gbModel.sizeFormatted, '3.0GB');
    });
  });
}
