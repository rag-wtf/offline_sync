import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';

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

    test('activeInferenceModelOrDefault falls back'
        ' for null or unknown ids', () {
      expect(
        ModelConfig.activeInferenceModelOrDefault(null),
        same(InferenceModels.gemma3_270M),
      );
      expect(
        ModelConfig.activeInferenceModelOrDefault('missing-model'),
        same(InferenceModels.gemma3_270M),
      );
    });

    test('Gemma 3 1B uses the verified LiteRT-LM bundle', () {
      const model = InferenceModels.gemma3_1B;

      expect(
        model.modelUrl,
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
        'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
      );
      expect(model.sizeBytes, 584417280);
      expect(
        model.sha256,
        '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be',
      );
    });
  });

  group('ModelDefinition', () {
    test('fileName extracts the trailing path segment', () {
      expect(EmbeddingModels.gecko64.fileName, 'Gecko_64_quant.tflite');
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

    test('repoPage derives the Hugging Face repo page from modelUrl', () {
      for (final model in ModelConfig.allModels) {
        expect(model.repoPage, startsWith('https://huggingface.co/'));
        expect(model.modelUrl, startsWith(model.repoPage));
        final uri = Uri.parse(model.repoPage);
        expect(
          uri.pathSegments.length,
          2,
          reason: '${model.id} repoPage should have org/repo path',
        );
      }
    });

    test('repoPage falls back to modelUrl when fewer than 2 segments', () {
      const shortModel = ModelDefinition(
        id: 'short',
        name: 'Short',
        modelUrl: 'https://example.com/single-segment',
        type: AppModelType.inference,
        sizeBytes: 100,
        minRamMB: 100,
        requiresGpu: false,
        tier: DeviceTier.low,
        maxTokens: 100,
      );
      expect(shortModel.repoPage, 'https://example.com/single-segment');
    });
  });

  group('ModelInfo', () {
    test('repoPage derives the Hugging Face repo page from url', () {
      final info = ModelInfo(
        id: 'test',
        name: 'Test',
        url:
            'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task',
        type: AppModelType.inference,
      );
      expect(
        info.repoPage,
        'https://huggingface.co/litert-community/gemma-3-270m-it',
      );
    });

    test('repoPage falls back to url when fewer than 2 segments', () {
      final info = ModelInfo(
        id: 'test',
        name: 'Test',
        url: 'https://example.com/single-segment',
        type: AppModelType.inference,
      );
      expect(info.repoPage, 'https://example.com/single-segment');
    });
  });
}
