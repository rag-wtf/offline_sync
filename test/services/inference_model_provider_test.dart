import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/model_config.dart';

import '../helpers/test_helpers.dart';

class _MockInferenceModel extends Mock implements InferenceModel {}

void main() {
  late MockRagSettingsService settings;

  setUp(() {
    settings = getAndRegisterMockRagSettingsService();
  });

  tearDown(unregisterTestHelpers);

  test('uses user-configured maxTokens and caches the loaded model', () async {
    final model = _MockInferenceModel();
    when(() => settings.maxTokens).thenReturn(1536);
    when(() => settings.activeInferenceModelId).thenReturn(null);

    var loadCalls = 0;
    final provider = InferenceModelProvider(
      activeModelLoader: ({required maxTokens}) async {
        loadCalls += 1;
        expect(maxTokens, 1536);
        return model;
      },
    );

    final first = await provider.getModel();
    final second = await provider.getModel();

    expect(first, same(model));
    expect(second, same(model));
    expect(loadCalls, 1);
  });

  test(
    'falls back to model config maxTokens when user setting is absent',
    () async {
      final model = _MockInferenceModel();
      const activeModelId = 'gemma-3n-E4B-it-int4';
      when(() => settings.maxTokens).thenReturn(null);
      when(() => settings.activeInferenceModelId).thenReturn(activeModelId);

      final provider = InferenceModelProvider(
        activeModelLoader: ({required maxTokens}) async {
          expect(
            maxTokens,
            ModelConfig.activeInferenceModelOrDefault(activeModelId).maxTokens,
          );
          return model;
        },
      );

      expect(await provider.getModel(), same(model));
    },
  );

  test('throws a clear error when the plugin loader throws', () async {
    when(() => settings.maxTokens).thenReturn(1024);
    when(() => settings.activeInferenceModelId).thenReturn(null);

    final provider = InferenceModelProvider(
      activeModelLoader: ({required maxTokens}) async {
        throw StateError('plugin offline');
      },
    );

    await expectLater(
      provider.getModel,
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Failed to get active inference model'),
        ),
      ),
    );
  });

  test('throws a clear error when the plugin'
      ' returns no active model', () async {
    when(() => settings.maxTokens).thenReturn(1024);
    when(() => settings.activeInferenceModelId).thenReturn(null);

    final provider = InferenceModelProvider(
      activeModelLoader: ({required maxTokens}) async => null,
    );

    await expectLater(
      provider.getModel,
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('No active inference model found'),
        ),
      ),
    );
  });

  test('clearCache forces the next read to reload the model', () async {
    final firstModel = _MockInferenceModel();
    final secondModel = _MockInferenceModel();
    when(() => settings.maxTokens).thenReturn(1024);
    when(() => settings.activeInferenceModelId).thenReturn(null);

    var loadCalls = 0;
    final provider = InferenceModelProvider(
      activeModelLoader: ({required maxTokens}) async {
        loadCalls += 1;
        return loadCalls == 1 ? firstModel : secondModel;
      },
    );

    expect(await provider.getModel(), same(firstModel));

    provider.clearCache();

    expect(await provider.getModel(), same(secondModel));
    expect(loadCalls, 2);
  });
}
