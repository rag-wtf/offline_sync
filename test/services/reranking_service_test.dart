import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/reranking_service.dart';
import 'package:offline_sync/services/vector_store.dart';

import '../helpers/test_helpers.dart';

class MockInferenceChat extends Mock implements InferenceChat {}

void main() {
  group('RerankingServiceTest -', () {
    late RerankingService service;
    late MockInferenceModelProvider mockModelProvider;
    late MockInferenceModel mockInferenceModel;

    setUpAll(() {
      registerFallbackValue(const Message(text: '', isUser: true));
    });

    setUp(() {
      mockModelProvider = getAndRegisterMockInferenceModelProvider();
      mockInferenceModel = MockInferenceModel();

      service = RerankingService();
    });

    tearDown(unregisterTestHelpers);

    group('rerank -', () {
      test('should sort candidates by relevance score', () async {
        const query = 'test query';
        final candidates = [
          SearchResult(id: '1', content: 'content 1', score: 0.1, metadata: {}),
          SearchResult(id: '2', content: 'content 2', score: 0.2, metadata: {}),
        ];

        when(
          () => mockModelProvider.getModel(),
        ).thenAnswer((_) async => mockInferenceModel);

        final mockChat = MockInferenceChat();
        when(
          () => mockInferenceModel.createChat(
            temperature: any(named: 'temperature'),
          ),
        ).thenAnswer((_) async => mockChat);

        when(mockChat.initSession).thenAnswer((_) async {});
        when(() => mockChat.addQuery(any())).thenAnswer((_) async {});

        // Sequential scores: result 1 gets 8.0, result 2 gets 9.5
        var callCount = 0;
        final scores = ['8.0', '9.5'];
        when(mockChat.generateChatResponseAsync).thenAnswer((_) {
          return Stream.fromIterable([TextResponse(scores[callCount++])]);
        });

        final results = await service.rerank(query, candidates, topK: 2);

        expect(results.length, 2);
        expect(results[0].id, '2'); // 9.5 comes first
        expect(results[0].score, 9.5);
        expect(results[1].id, '1'); // 8.0 comes second
        expect(results[1].score, 8.0);
      });

      test('fallback to original candidates on model error', () async {
        final candidates = [
          SearchResult(id: '1', content: 'c1', score: 0.5, metadata: {}),
        ];
        when(
          () => mockModelProvider.getModel(),
        ).thenThrow(Exception('Model error'));

        final result = await service.rerank('q', candidates);

        expect(result, candidates);
      });

      test('uses a neutral score when scoring a chunk throws', () async {
        const query = 'test query';
        final candidates = [
          SearchResult(id: '1', content: 'c1', score: 0.5, metadata: {}),
        ];

        when(
          () => mockModelProvider.getModel(),
        ).thenAnswer((_) async => mockInferenceModel);

        final mockChat = MockInferenceChat();
        when(
          () => mockInferenceModel.createChat(
            temperature: any(named: 'temperature'),
          ),
        ).thenAnswer((_) async => mockChat);

        when(mockChat.initSession).thenAnswer((_) async {});
        when(
          () => mockChat.addQuery(any()),
        ).thenThrow(Exception('prompt failed'));

        final result = await service.rerank(query, candidates, topK: 1);

        expect(result.single.id, '1');
        expect(result.single.score, 5.0);
      });

      test('truncates content longer than maxCharsForReranking', () async {
        const query = 'test query';
        final longContent = 'A' * 600;
        final candidates = [
          SearchResult(id: '1', content: longContent, score: 0.5, metadata: {}),
        ];

        when(
          () => mockModelProvider.getModel(),
        ).thenAnswer((_) async => mockInferenceModel);

        final mockChat = MockInferenceChat();
        when(
          () => mockInferenceModel.createChat(
            temperature: any(named: 'temperature'),
          ),
        ).thenAnswer((_) async => mockChat);

        when(mockChat.initSession).thenAnswer((_) async {});
        Message? capturedMessage;
        when(() => mockChat.addQuery(any())).thenAnswer((invocation) async {
          capturedMessage = invocation.positionalArguments.first as Message;
        });
        when(mockChat.generateChatResponseAsync).thenAnswer(
          (_) => Stream.fromIterable([const TextResponse('9.0')]),
        );

        final results = await service.rerank(query, candidates, topK: 1);

        expect(results.single.score, 9.0);
        expect(capturedMessage, isNotNull);
        expect(capturedMessage!.text, contains('...'));
      });
    });
  });
}
