import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/model_config.dart';

import '../helpers/test_helpers.dart';

class _MockInferenceModel extends Mock implements InferenceModel {}

class _MockInferenceChat extends Mock implements InferenceChat {}

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

  test(
    'serialized chat operations close their chat on success and failure',
    () async {
      final model = _MockInferenceModel();
      final chat = _MockInferenceChat();
      when(
        () => model.createChat(temperature: any(named: 'temperature')),
      ).thenAnswer((_) async => chat);
      when(chat.close).thenAnswer((_) async {});

      await InferenceModelProvider.withSerializedChat<void>(
        model,
        temperature: 0.1,
        action: (_) async {},
      );
      verify(chat.close).called(1);

      await expectLater(
        InferenceModelProvider.withSerializedChat<void>(
          model,
          temperature: 0.1,
          action: (_) async => throw StateError('generation failed'),
        ),
        throwsStateError,
      );
    verify(chat.close).called(1);
    },
  );

  test('clearCache closes the cached model', () async {
    final model = _MockInferenceModel();
    when(() => settings.maxTokens).thenReturn(1024);
    when(() => settings.activeInferenceModelId).thenReturn(null);
    when(model.close).thenAnswer((_) async {});
    final provider = InferenceModelProvider(
      activeModelLoader: ({required maxTokens}) async => model,
    );

    await provider.getModel();
    provider.clearCache();
    await Future<void>.delayed(Duration.zero);

    verify(model.close).called(1);
  });
}
