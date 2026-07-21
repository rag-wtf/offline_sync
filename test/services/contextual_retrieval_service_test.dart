import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/contextual_retrieval_service.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';

class MockDeviceCapabilityService extends Mock
    implements DeviceCapabilityService {}

class MockModelRecommendationService extends Mock
    implements ModelRecommendationService {}

class MockRagSettingsService extends Mock implements RagSettingsService {}

class MockInferenceModel extends Mock implements InferenceModel {}

class MockInferenceChat extends Mock implements InferenceChat {}

class TestContextualRetrievalService extends ContextualRetrievalService {
  TestContextualRetrievalService({Map<String, String>? contexts})
    : _contexts = contexts ?? const {};

  final Map<String, String> _contexts;
  final List<String> capturedDocumentContent = [];
  final List<String> capturedChunks = [];

  @override
  Future<String> generateChunkContext({
    required String documentContent,
    required String chunk,
  }) async {
    capturedDocumentContent.add(documentContent);
    capturedChunks.add(chunk);
    return _contexts[chunk] ?? '';
  }
}

void main() {
  group('ContextualRetrievalService Tests -', () {
    late ContextualRetrievalService service;
    late MockDeviceCapabilityService mockDeviceService;
    late MockModelRecommendationService mockRecommendationService;
    late MockRagSettingsService mockSettingsService;

    setUpAll(() {
      registerFallbackValue(const Message(text: '', isUser: true));
      registerFallbackValue(
        const DeviceCapabilities(
          totalRamMB: 0,
          availableStorageMB: 0,
          hasGpu: false,
          platform: '',
        ),
      );
    });

    setUp(() async {
      await locator.reset();

      mockDeviceService = MockDeviceCapabilityService();
      mockRecommendationService = MockModelRecommendationService();
      mockSettingsService = MockRagSettingsService();

      locator
        ..registerSingleton<DeviceCapabilityService>(mockDeviceService)
        ..registerSingleton<ModelRecommendationService>(
          mockRecommendationService,
        )
        ..registerSingleton<RagSettingsService>(mockSettingsService);

      service = ContextualRetrievalService();
    });

    tearDown(() async {
      ContextualRetrievalService.getActiveModel = FlutterGemma.getActiveModel;
      await locator.reset();
    });

    group('isSupported -', () {
      test('should return false when disabled in settings', () async {
        when(
          () => mockSettingsService.contextualRetrievalEnabled,
        ).thenReturn(false);

        expect(await service.isSupported, isFalse);

        verifyNever(() => mockDeviceService.getCapabilities());
      });

      test('should return true for High tier device when enabled', () async {
        when(
          () => mockSettingsService.contextualRetrievalEnabled,
        ).thenReturn(true);

        when(() => mockDeviceService.getCapabilities()).thenAnswer(
          (_) async => const DeviceCapabilities(
            totalRamMB: 4096,
            availableStorageMB: 2048,
            hasGpu: true,
            platform: 'android',
          ),
        );

        when(
          () => mockRecommendationService.getRecommendedModels(any()),
        ).thenReturn(
          const RecommendedModels(
            tier: DeviceTier.high,
            inferenceModel: InferenceModels.gemma3n_2B,
            embeddingModel: EmbeddingModels.embeddingGemma512,
          ),
        );

        expect(await service.isSupported, isTrue);
      });

      test('should return true for Premium tier device when enabled', () async {
        when(
          () => mockSettingsService.contextualRetrievalEnabled,
        ).thenReturn(true);

        when(() => mockDeviceService.getCapabilities()).thenAnswer(
          (_) async => const DeviceCapabilities(
            totalRamMB: 8192,
            availableStorageMB: 4096,
            hasGpu: true,
            platform: 'linux',
          ),
        );

        when(
          () => mockRecommendationService.getRecommendedModels(any()),
        ).thenReturn(
          const RecommendedModels(
            tier: DeviceTier.premium,
            inferenceModel: InferenceModels.gemma3n_4B,
            embeddingModel: EmbeddingModels.embeddingGemma1024,
          ),
        );

        expect(await service.isSupported, isTrue);
      });

      test('should return false for Low tier device', () async {
        when(
          () => mockSettingsService.contextualRetrievalEnabled,
        ).thenReturn(true);

        when(() => mockDeviceService.getCapabilities()).thenAnswer(
          (_) async => const DeviceCapabilities(
            totalRamMB: 1024,
            availableStorageMB: 512,
            hasGpu: false,
            platform: 'android',
          ),
        );

        when(
          () => mockRecommendationService.getRecommendedModels(any()),
        ).thenReturn(
          const RecommendedModels(
            tier: DeviceTier.low,
            inferenceModel: InferenceModels.gemma3_270M,
            embeddingModel: EmbeddingModels.gecko64,
          ),
        );

        expect(await service.isSupported, isFalse);
      });

      test('should return false for Mid tier device', () async {
        when(
          () => mockSettingsService.contextualRetrievalEnabled,
        ).thenReturn(true);

        when(() => mockDeviceService.getCapabilities()).thenAnswer(
          (_) async => const DeviceCapabilities(
            totalRamMB: 2048,
            availableStorageMB: 1024,
            hasGpu: false,
            platform: 'android',
          ),
        );

        when(
          () => mockRecommendationService.getRecommendedModels(any()),
        ).thenReturn(
          const RecommendedModels(
            tier: DeviceTier.mid,
            inferenceModel: InferenceModels.gemma3_1B,
            embeddingModel: EmbeddingModels.embeddingGemma256,
          ),
        );

        expect(await service.isSupported, isFalse);
      });
    });

    group('canProcessFullDocument -', () {
      test('should return true for small documents', () {
        // Small doc that fits within token budget
        const smallDocChars = 1000; // ~250 tokens
        expect(service.canProcessFullDocument(smallDocChars), isTrue);
      });

      test('should return false for very large documents', () {
        // Very large doc that exceeds token budget
        const largeDocChars = 50000; // ~12,500 tokens
        expect(service.canProcessFullDocument(largeDocChars), isFalse);
      });

      test('should return true for documents at boundary', () {
        // Document close to the limit
        const boundaryChars = 4000; // ~1000 tokens
        expect(service.canProcessFullDocument(boundaryChars), isTrue);
      });
    });

    group('contextualizeDocument -', () {
      test('generateChunkContext builds a prompt and trims the response', () async {
        final model = MockInferenceModel();
        final chat = MockInferenceChat();
        Message? capturedPrompt;

        ContextualRetrievalService.getActiveModel = () async => model;
        when(
          () => model.createChat(temperature: any(named: 'temperature')),
        ).thenAnswer((_) async => chat);
        when(chat.initSession).thenAnswer((_) async {});
        when(() => chat.addQuery(any())).thenAnswer((invocation) async {
          capturedPrompt = invocation.positionalArguments.single as Message;
        });
        when(chat.generateChatResponseAsync).thenAnswer(
          (_) => Stream<ModelResponse>.fromIterable([
            const TextResponse('  Context'),
            const TextResponse(' summary  '),
          ]),
        );

        final response = await service.generateChunkContext(
          documentContent: 'Full document body',
          chunk: 'Target chunk',
        );

        expect(response, 'Context summary');
        expect(capturedPrompt, isNotNull);
        expect(capturedPrompt!.text, contains('Target chunk'));
        expect(capturedPrompt!.text, contains('Full document body'));
      });

      test('generateChunkContext falls back to empty text on model errors', () async {
        ContextualRetrievalService.getActiveModel =
            () async => throw Exception('missing model');

        final response = await service.generateChunkContext(
          documentContent: 'Full document body',
          chunk: 'Target chunk',
        );

        expect(response, isEmpty);
      });

      test(
        'should contextualize chunks with full document context and '
        'report progress',
        () async {
          final testService = TestContextualRetrievalService(
            contexts: {
              'Chunk 1': 'Context for chunk 1',
              'Chunk 2': 'Context for chunk 2',
            },
          );
          final chunks = ['Chunk 1', 'Chunk 2'];
          const documentContent = 'Full document content here.';

          var progressCalls = 0;
          var lastCompleted = 0;
          var lastTotal = 0;

          final results = await testService.contextualizeDocument(
            documentContent: documentContent,
            chunks: chunks,
            onProgress: (completed, total) {
              progressCalls++;
              lastCompleted = completed;
              lastTotal = total;
            },
          );

          expect(progressCalls, equals(chunks.length));
          expect(lastCompleted, equals(chunks.length));
          expect(lastTotal, equals(chunks.length));
          expect(testService.capturedChunks, equals(chunks));
          expect(
            testService.capturedDocumentContent,
            everyElement(equals(documentContent)),
          );
          expect(results.length, equals(chunks.length));
          expect(results[0].originalContent, 'Chunk 1');
          expect(results[0].context, 'Context for chunk 1');
          expect(results[0].combinedContent, 'Context for chunk 1\n\nChunk 1');
          expect(results[1].combinedContent, 'Context for chunk 2\n\nChunk 2');
        },
      );

      test(
        'should preserve original chunk when contextual generation returns '
        'empty',
        () async {
          final testService = TestContextualRetrievalService();
          final results = await testService.contextualizeDocument(
            documentContent: 'Full document content here.',
            chunks: const ['Chunk 1'],
          );

          expect(results.single.originalContent, 'Chunk 1');
          expect(results.single.context, isEmpty);
          expect(results.single.combinedContent, 'Chunk 1');
        },
      );

      test('should use sliding window for large documents', () async {
        final testService = TestContextualRetrievalService(
          contexts: {'Target chunk': 'Windowed context'},
        );
        final largePrefix = 'A' * 25000;
        final largeSuffix = 'B' * 25000;
        final largeDocument = '$largePrefix\nTarget chunk\n$largeSuffix';

        final results = await testService.contextualizeDocument(
          documentContent: largeDocument,
          chunks: const ['Target chunk'],
        );

        expect(
          results.single.combinedContent,
          'Windowed context\n\nTarget chunk',
        );
        expect(
          testService.capturedDocumentContent.single,
          isNot(largeDocument),
        );
        expect(
          testService.capturedDocumentContent.single.length,
          lessThan(largeDocument.length),
        );
        expect(
          testService.capturedDocumentContent.single,
          contains('Target chunk'),
        );
      });

      test(
        'should use the leading window when chunk is absent from a large '
        'document',
        () async {
          final testService = TestContextualRetrievalService();
          final largeDocument = '${'Lead' * 3000}${'Tail' * 3000}';

          await testService.contextualizeDocument(
            documentContent: largeDocument,
            chunks: const ['Missing chunk'],
          );

          final captured = testService.capturedDocumentContent.single;
          expect(captured.length, lessThan(largeDocument.length));
          expect(captured, equals(largeDocument.substring(0, captured.length)));
        },
      );

      test('should process all chunks and call progress callback', () async {
        final chunks = ['Chunk 1', 'Chunk 2', 'Chunk 3'];
        const documentContent = 'Full document content here.';

        var progressCalls = 0;
        var lastCompleted = 0;
        var lastTotal = 0;
        final testService = TestContextualRetrievalService();

        final results = await testService.contextualizeDocument(
          documentContent: documentContent,
          chunks: chunks,
          onProgress: (completed, total) {
            progressCalls++;
            lastCompleted = completed;
            lastTotal = total;
          },
        );

        expect(progressCalls, equals(chunks.length));
        expect(lastCompleted, equals(chunks.length));
        expect(lastTotal, equals(chunks.length));
        expect(results.length, equals(chunks.length));
        for (var i = 0; i < results.length; i++) {
          expect(results[i].originalContent, equals(chunks[i]));
        }
      });
    });

    group('ContextualizedChunk -', () {
      test('should create chunk with all required fields', () {
        const chunk = ContextualizedChunk(
          originalContent: 'Original',
          context: 'Context info',
          combinedContent: 'Context info\n\nOriginal',
        );

        expect(chunk.originalContent, 'Original');
        expect(chunk.context, 'Context info');
        expect(chunk.combinedContent, 'Context info\n\nOriginal');
      });

      test('should handle empty context', () {
        const chunk = ContextualizedChunk(
          originalContent: 'Original',
          context: '',
          combinedContent: 'Original',
        );

        expect(chunk.originalContent, 'Original');
        expect(chunk.context, isEmpty);
        expect(chunk.combinedContent, 'Original');
      });
    });

    group('Edge cases -', () {
      test('should handle empty chunks list', () async {
        final testService = TestContextualRetrievalService();
        final results = await testService.contextualizeDocument(
          documentContent: 'Some content',
          chunks: [],
        );

        expect(results, isEmpty);
      });

      test('should handle empty document content', () async {
        final testService = TestContextualRetrievalService();
        final results = await testService.contextualizeDocument(
          documentContent: '',
          chunks: const ['Chunk 1'],
        );

        expect(results.length, equals(1));
        expect(testService.capturedDocumentContent.single, isEmpty);
      });
    });
  });
}
