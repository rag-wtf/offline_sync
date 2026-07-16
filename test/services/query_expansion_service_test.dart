import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/query_expansion_service.dart';
import 'package:offline_sync/services/vector_store.dart';

import '../helpers/test_helpers.dart';

class MockInferenceChat extends Mock implements InferenceChat {}

void main() {
  group('QueryExpansionServiceTest -', () {
    late QueryExpansionService service;
    late MockVectorStore mockVectorStore;
    late MockInferenceModelProvider mockModelProvider;
    late MockInferenceModel mockInferenceModel;
    late MockEmbeddingService mockEmbeddingService;

    setUpAll(() {
      registerFallbackValue(const Message(text: '', isUser: true));
    });

    setUp(() {
      mockVectorStore = getAndRegisterMockVectorStore();
      mockModelProvider = getAndRegisterMockInferenceModelProvider();
      mockInferenceModel = MockInferenceModel();
      mockEmbeddingService = getAndRegisterMockEmbeddingService();

      service = QueryExpansionService();
    });

    tearDown(unregisterTestHelpers);

    group('expandQuery -', () {
      test('should return variants from model', () async {
        const query = 'original query';

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
        when(mockChat.generateChatResponseAsync).thenAnswer(
          (_) =>
              Stream.fromIterable([const TextResponse('variant 1\nvariant 2')]),
        );

        final result = await service.expandQuery(query);

        expect(result, contains(query));
        expect(result, contains('variant 1'));
        expect(result, contains('variant 2'));
        expect(result.length, 3);
      });

      test('fallback to original query on error', () async {
        const query = 'original query';
        when(
          () => mockModelProvider.getModel(),
        ).thenThrow(Exception('Model error'));

        final result = await service.expandQuery(query);

        expect(result, [query]);
      });
    });

    group('searchWithExpandedQueries -', () {
      test('should search with all variants and merge results', () async {
        final variants = ['v1', 'v2'];
        final embedding = [0.1];

        when(
          () => mockEmbeddingService.generateEmbedding(any()),
        ).thenAnswer((_) async => embedding);

        when(
          () => mockVectorStore.hybridSearch(
            any(),
            any(),
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer(
          (_) async => [
            SearchResult(id: '1', content: 'c1', score: 0.9, metadata: {}),
          ],
        );

        final results = await service.searchWithExpandedQueries('q', variants);

        expect(results.length, 1);
        expect(results[0].id, '1');
        verify(
          () => mockVectorStore.hybridSearch('v1', embedding, limit: 20),
        ).called(1);
        verify(
          () => mockVectorStore.hybridSearch('v2', embedding, limit: 20),
        ).called(1);
      });
    });
  });
}
