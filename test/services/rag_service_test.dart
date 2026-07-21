import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/rag_token_manager.dart';
import 'package:offline_sync/services/vector_store.dart';

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
    late MockQueryExpansionService mockQueryExpansionService;
    late MockRerankingService mockRerankingService;

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
      mockQueryExpansionService = getAndRegisterMockQueryExpansionService();
      mockRerankingService = getAndRegisterMockRerankingService();

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
          'Message 1',
          'Message 2',
          'Message 3',
        ];

        final result = locator<RagTokenManager>().buildHistoryWithBudget(
          history,
          5,
        );

        expect(result, isNot(contains('Message 1')));
        expect(result, contains('Message 2'));
        expect(result, contains('Message 3'));
      });
    });

    test('requires initialization before querying or streaming', () async {
      await expectLater(service.askWithRAG('query'), throwsException);
      await expectLater(
        service.askWithRAGStream('query').drain<void>(),
        throwsException,
      );
    });

    test('initialize is idempotent', () async {
      when(() => mockVectorStore.initialize()).thenAnswer((_) async {});

      await service.initialize();
      await service.initialize();

      verify(() => mockVectorStore.initialize()).called(1);
    });

    test('splitIntoChunks keeps short text intact and splits long lines', () {
      expect(service.splitIntoChunks('short text', 80), ['short text']);
      final chunks = service.splitIntoChunks('x' * 5000, 80, overlapPercent: 0);
      expect(chunks.length, greaterThan(1));
      expect(chunks.join().length, 5000);
    });

    test('ingestDocument embeds chunks and writes a batch', () async {
      when(() => mockSettingsService.chunkOverlapPercent).thenReturn(0);
      when(
        () => mockEmbeddingService.generateEmbedding(any<String>()),
      ).thenAnswer((_) async => [0.1, 0.2]);
      when(
        () => mockVectorStore.insertEmbeddingsBatch(any<List<EmbeddingData>>()),
      ).thenReturn(null);

      await service.ingestDocument('doc', 'A short document');

      verify(
        () => mockEmbeddingService.generateEmbedding('A short document'),
      ).called(1);
      final captured =
          verify(
                () => mockVectorStore.insertEmbeddingsBatch(captureAny()),
              ).captured.single
              as List<EmbeddingData>;
      expect(captured.single.documentId, 'doc');
      expect(captured.single.metadata, {'seq': 0});
    });

    test('stream emits metadata, text tokens, and completion', () async {
      when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
      await service.initialize();
      when(() => mockSettingsService.rerankingEnabled).thenReturn(false);
      when(() => mockSettingsService.searchTopK).thenReturn(5);
      when(
        () => mockEmbeddingService.generateEmbedding('stream'),
      ).thenAnswer((_) async => [0.1]);
      when(
        () => mockVectorStore.hybridSearch(
          any(),
          any(),
          limit: any(named: 'limit'),
          documentIds: any(named: 'documentIds'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockModelProvider.getModel(),
      ).thenAnswer((_) async => mockInferenceModel);
      final chat = MockInferenceChat();
      when(
        () => mockInferenceModel.createChat(
          temperature: any(named: 'temperature'),
        ),
      ).thenAnswer((_) async => chat);
      when(chat.initSession).thenAnswer((_) async {});
      when(() => chat.addQuery(any())).thenAnswer((_) async {});
      when(chat.generateChatResponseAsync).thenAnswer(
        (_) => Stream<ModelResponse>.fromIterable([const TextResponse('one')]),
      );

      final events = await service.askWithRAGStream('stream').toList();

      expect(events.first, isA<RAGMetadataEvent>());
      expect(events.whereType<RAGTokenEvent>().map((e) => e.token), ['one']);
      expect(events.last, isA<RAGCompleteEvent>());
    });

    group('askWithRAG -', () {
      Future<void> arrangeGeneration({
        String response = 'Mocked response',
        Future<void> Function(Message message)? onAddQuery,
        Stream<ModelResponse>? stream,
      }) async {
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
        when(() => mockChat.addQuery(any())).thenAnswer((invocation) async {
          if (onAddQuery != null) {
            await onAddQuery(invocation.positionalArguments.first as Message);
          }
        });
        when(mockChat.generateChatResponseAsync).thenAnswer(
          (_) =>
              stream ??
              Stream<ModelResponse>.fromIterable([TextResponse(response)]),
        );
      }

      test('should call searchSimilar and return response', () async {
        const query = 'Test query';
        final embedding = [0.1, 0.2, 0.3];

        when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
        await service.initialize();

        when(
          () => mockEmbeddingService.generateEmbedding(query),
        ).thenAnswer((_) async => embedding);
        when(
          () => mockVectorStore.hybridSearch(
            any(),
            any(),
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer((_) async => []);
        await arrangeGeneration();

        when(() => mockSettingsService.searchTopK).thenReturn(5);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(false);

        final result = await service.askWithRAG(query);

        expect(result.response, 'Mocked response');
        verify(
          () => mockVectorStore.hybridSearch(query, embedding),
        ).called(1);
      });

      test('uses expanded queries when query expansion is enabled', () async {
        const query = 'Test query';
        final embedding = [0.1, 0.2, 0.3];
        final expandedQueries = [query, 'Expanded query'];

        when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
        await service.initialize();

        when(
          () => mockEmbeddingService.generateEmbedding(query),
        ).thenAnswer((_) async => embedding);
        when(() => mockSettingsService.queryExpansionEnabled).thenReturn(true);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(false);
        when(() => mockSettingsService.searchTopK).thenReturn(3);
        when(
          () => mockQueryExpansionService.expandQuery(query),
        ).thenAnswer((_) async => expandedQueries);
        when(
          () => mockQueryExpansionService.searchWithExpandedQueries(
            query,
            expandedQueries,
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer((_) async => []);
        await arrangeGeneration();

        await service.askWithRAG(query);

        verify(
          () => mockQueryExpansionService.searchWithExpandedQueries(
            query,
            expandedQueries,
            limit: 3,
          ),
        ).called(1);
        verifyNever(() => mockVectorStore.hybridSearch(any(), any()));
      });

      test(
        'falls back to hybrid search when expansion returns only the original query',
        () async {
          const query = 'Test query';
          final embedding = [0.1, 0.2, 0.3];

          when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
          await service.initialize();

          when(
            () => mockEmbeddingService.generateEmbedding(query),
          ).thenAnswer((_) async => embedding);
          when(() => mockSettingsService.queryExpansionEnabled).thenReturn(true);
          when(() => mockSettingsService.rerankingEnabled).thenReturn(false);
          when(() => mockSettingsService.searchTopK).thenReturn(3);
          when(
            () => mockQueryExpansionService.expandQuery(query),
          ).thenAnswer((_) async => [query]);
          when(
            () => mockVectorStore.hybridSearch(
              query,
              embedding,
              limit: any(named: 'limit'),
              documentIds: any(named: 'documentIds'),
            ),
          ).thenAnswer((_) async => []);
          await arrangeGeneration();

          final result = await service.askWithRAG(query, includeMetrics: true);

          verifyNever(
            () => mockQueryExpansionService.searchWithExpandedQueries(
              any(),
              any(),
              limit: any(named: 'limit'),
              documentIds: any(named: 'documentIds'),
            ),
          );
          verify(
            () => mockVectorStore.hybridSearch(
              query,
              embedding,
              limit: 3,
              documentIds: any(named: 'documentIds'),
            ),
          ).called(1);
          expect(result.metrics?.expandedQueryCount, 1);
          expect(result.metrics?.queryExpansionTime, isNotNull);
        },
      );

      test('reranks results and trims them to searchTopK', () async {
        const query = 'Test query';
        final embedding = [0.1, 0.2, 0.3];
        final initialResults = [
          SearchResult(id: '1', content: 'First', score: 0.1, metadata: {}),
          SearchResult(id: '2', content: 'Second', score: 0.2, metadata: {}),
          SearchResult(id: '3', content: 'Third', score: 0.3, metadata: {}),
        ];
        final rerankedResults = [
          SearchResult(id: '3', content: 'Third', score: 9, metadata: {}),
          SearchResult(id: '2', content: 'Second', score: 8, metadata: {}),
          SearchResult(id: '1', content: 'First', score: 7, metadata: {}),
        ];

        when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
        await service.initialize();

        when(
          () => mockEmbeddingService.generateEmbedding(query),
        ).thenAnswer((_) async => embedding);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(true);
        when(() => mockSettingsService.rerankTopK).thenReturn(3);
        when(() => mockSettingsService.searchTopK).thenReturn(2);
        when(
          () => mockVectorStore.hybridSearch(
            query,
            embedding,
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer((_) async => initialResults);
        when(
          () => mockRerankingService.rerank(
            query,
            initialResults,
            topK: any(named: 'topK'),
          ),
        ).thenAnswer((_) async => rerankedResults);
        await arrangeGeneration();

        final result = await service.askWithRAG(query);

        verify(
          () => mockVectorStore.hybridSearch(
            query,
            embedding,
            limit: 3,
          ),
        ).called(1);
        verify(
          () => mockRerankingService.rerank(
            query,
            initialResults,
            topK: 3,
          ),
        ).called(1);
        expect(result.sources.map((source) => source.id).toList(), ['3', '2']);
      });

      test('forwards documentIds to retrieval', () async {
        const query = 'Test query';
        final embedding = [0.1, 0.2, 0.3];
        const documentIds = ['doc-1', 'doc-2'];

        when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
        await service.initialize();

        when(
          () => mockEmbeddingService.generateEmbedding(query),
        ).thenAnswer((_) async => embedding);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(false);
        when(() => mockSettingsService.searchTopK).thenReturn(4);
        when(
          () => mockVectorStore.hybridSearch(
            query,
            embedding,
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer((_) async => []);
        await arrangeGeneration();

        await service.askWithRAG(query, documentIds: documentIds);

        verify(
          () => mockVectorStore.hybridSearch(
            query,
            embedding,
            limit: 4,
            documentIds: documentIds,
          ),
        ).called(1);
      });

      test(
        'uses no-context fallback text when retrieval returns nothing',
        () async {
          const query = 'Test query';
          final embedding = [0.1, 0.2, 0.3];
          Message? promptMessage;

          when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
          await service.initialize();

          when(
            () => mockEmbeddingService.generateEmbedding(query),
          ).thenAnswer((_) async => embedding);
          when(() => mockSettingsService.rerankingEnabled).thenReturn(false);
          when(
            () => mockVectorStore.hybridSearch(
              query,
              embedding,
              limit: any(named: 'limit'),
              documentIds: any(named: 'documentIds'),
            ),
          ).thenAnswer((_) async => []);
          await arrangeGeneration(
            onAddQuery: (message) async {
              promptMessage = message;
            },
          );

          await service.askWithRAG(query);

          expect(promptMessage, isNotNull);
          expect(promptMessage!.text, contains('No relevant context found.'));
        },
      );

      test('surfaces generation errors', () async {
        const query = 'Test query';
        final embedding = [0.1, 0.2, 0.3];

        when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
        await service.initialize();

        when(
          () => mockEmbeddingService.generateEmbedding(query),
        ).thenAnswer((_) async => embedding);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(false);
        when(
          () => mockVectorStore.hybridSearch(
            query,
            embedding,
            limit: any(named: 'limit'),
            documentIds: any(named: 'documentIds'),
          ),
        ).thenAnswer((_) async => []);
        await arrangeGeneration(
          stream: Stream<ModelResponse>.error(Exception('generation failed')),
        );

        await expectLater(
          service.askWithRAG(query),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('generation failed'),
            ),
          ),
        );
      });
    });

    group('askWithRAGStream -', () {
      test('uses configured searchTopK for retrieval limit', () async {
        const query = 'Stream query';
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
        when(
          mockChat.generateChatResponseAsync,
        ).thenAnswer((_) => const Stream.empty());

        when(() => mockSettingsService.searchTopK).thenReturn(7);
        when(() => mockSettingsService.rerankingEnabled).thenReturn(false);

        await service.askWithRAGStream(query).drain<void>();

        verify(
          () => mockVectorStore.hybridSearch(
            query,
            embedding,
            limit: 7,
            documentIds: any(named: 'documentIds'),
          ),
        ).called(1);
      });

      test(
        'expands, reranks, and reports metrics when streaming with includeMetrics',
        () async {
          const query = 'Stream query';
          final embedding = [0.1, 0.2, 0.3];
          final initialResults = [
            SearchResult(id: '1', content: 'First', score: 0.1, metadata: {}),
            SearchResult(id: '2', content: 'Second', score: 0.2, metadata: {}),
            SearchResult(id: '3', content: 'Third', score: 0.3, metadata: {}),
          ];
          final rerankedResults = [
            SearchResult(id: '3', content: 'Third', score: 9, metadata: {}),
            SearchResult(id: '2', content: 'Second', score: 8, metadata: {}),
            SearchResult(id: '1', content: 'First', score: 7, metadata: {}),
          ];

          when(() => mockVectorStore.initialize()).thenAnswer((_) async {});
          await service.initialize();

          when(
            () => mockEmbeddingService.generateEmbedding(query),
          ).thenAnswer((_) async => embedding);
          when(() => mockSettingsService.queryExpansionEnabled).thenReturn(true);
          when(() => mockSettingsService.rerankingEnabled).thenReturn(true);
          when(() => mockSettingsService.rerankTopK).thenReturn(3);
          when(() => mockSettingsService.searchTopK).thenReturn(2);
          when(
            () => mockQueryExpansionService.expandQuery(query),
          ).thenAnswer((_) async => [query, 'Expanded']);
          when(
            () => mockQueryExpansionService.searchWithExpandedQueries(
              query,
              [query, 'Expanded'],
              limit: any(named: 'limit'),
              documentIds: any(named: 'documentIds'),
            ),
          ).thenAnswer((_) async => initialResults);
          when(
            () => mockRerankingService.rerank(
              query,
              initialResults,
              topK: any(named: 'topK'),
            ),
          ).thenAnswer((_) async => rerankedResults);
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
          when(
            mockChat.generateChatResponseAsync,
          ).thenAnswer((_) => Stream<ModelResponse>.value(const TextResponse('done')));

          final events = await service
              .askWithRAGStream(query, includeMetrics: true)
              .toList();

          final metadata = events.first as RAGMetadataEvent;
          expect(metadata.sources.map((result) => result.id).toList(), ['3', '2']);
          expect(metadata.metrics?.queryExpansionTime, isNotNull);
          expect(metadata.metrics?.rerankingTime, isNotNull);
          expect(metadata.metrics?.expandedQueryCount, 2);
          expect(events.whereType<RAGTokenEvent>().single.token, 'done');
          expect(events.last, isA<RAGCompleteEvent>());
        },
      );
    });
  });
}
