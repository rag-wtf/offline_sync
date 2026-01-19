import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/rag_token_manager.dart';

import '../helpers/test_helpers.dart';

class MockInferenceChat extends Mock implements InferenceChat {}

void main() {
  group('RagServiceTest -', () {
    late RagService service;
    late MockVectorStore mockVectorStore;
    late MockInferenceModelProvider mockModelProvider;
    late MockInferenceModel mockInferenceModel;
    late MockRagSettingsService mockSettingsService;
    late MockEmbeddingService mockEmbeddingService;

    setUpAll(() {
      registerFallbackValue(const Message(text: '', isUser: true));
    });

    setUp(() {
      getAndRegisterMockRagTokenManager();
      mockVectorStore = getAndRegisterMockVectorStore();
      mockModelProvider = getAndRegisterMockInferenceModelProvider();
      mockInferenceModel = MockInferenceModel();
      mockSettingsService = getAndRegisterMockRagSettingsService();
      mockEmbeddingService = getAndRegisterMockEmbeddingService();

      service = RagService();
    });

    tearDown(unregisterTestHelpers);

    group('buildHistoryWithBudget -', () {
      test('when budget is large enough, should return all history', () {
        final history = [
          'User: Hello',
          'Model: Hi there!',
        ];

        final result = locator<RagTokenManager>().buildHistoryWithBudget(
          history,
          100,
        );

        expect(result, contains('User: Hello'));
        expect(result, contains('Model: Hi there!'));
      });

      test('when budget is small, should truncate history from oldest', () {
        final history = [
          'Message 1', // Oldest
          'Message 2',
          'Message 3', // Newest
        ];

        // Each message is roughly 9 chars -> ~3 tokens
        // Last 2 messages are always kept (6 tokens)
        final result = locator<RagTokenManager>().buildHistoryWithBudget(
          history,
          5, // Not enough for all 3
        );

        expect(result, isNot(contains('Message 1')));
        expect(result, contains('Message 2'));
        expect(result, contains('Message 3'));
      });
    });

    group('askWithRAG -', () {
      test('should call searchSimilar and return response', () async {
        const query = 'Test query';
        final embedding = [0.1, 0.2, 0.3];

        when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
        await service.initialize();

        when(
          () => mockEmbeddingService.generateEmbedding(query),
        ).thenAnswer((_) async => embedding);

        when(
          () => mockModelProvider.getModel(),
        ).thenAnswer((_) async => mockInferenceModel);

        when(
          () => mockVectorStore.hybridSearch(
            any(),
            any(),
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer((_) async => []);

        final mockChat = MockInferenceChat();
        when(
          () => mockInferenceModel.createChat(
            temperature: any(named: 'temperature'),
          ),
        ).thenAnswer((_) async => mockChat);

        when(mockChat.initSession).thenAnswer((_) async {});
        when(() => mockChat.addQuery(any())).thenAnswer((_) async {});
        when(mockChat.generateChatResponseAsync).thenAnswer(
          (_) => Stream.fromIterable([const TextResponse('Mocked response')]),
        );

        when(() => mockSettingsService.searchTopK).thenReturn(5);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(false);

        final result = await service.askWithRAG(query);

        expect(result.response, 'Mocked response');
        verify(
          () => mockVectorStore.hybridSearch(query, embedding),
        ).called(1);
      });
    });
  });
}
