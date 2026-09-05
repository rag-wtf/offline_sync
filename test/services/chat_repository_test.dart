import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Mock PathProvider
class MockPathProviderPlatform extends PathProviderPlatform {
  MockPathProviderPlatform(this.tempDir);
  final Directory tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
}

void main() {
  group('ChatRepositoryTest -', () {
    late ChatRepository chatRepository;
    late VectorStore vectorStore;
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();

      // Create a temporary directory for each test
      tempDir = Directory.systemTemp.createTempSync('chat_repo_test_');
      PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);

      await locator.reset();
      vectorStore = VectorStore();
      await vectorStore.initialize();

      locator.registerSingleton<VectorStore>(vectorStore);

      chatRepository = ChatRepository()..initialize();
    });

    tearDown(() async {
      await vectorStore.close();
      await locator.reset();

      // Clean up the temporary directory
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saveMessage saves message to database', () async {
      final message = ChatMessage(
        content: 'Hello World',
        isUser: true,
        timestamp: DateTime.now(),
      );

      await chatRepository.saveMessage(message);

      final count = await chatRepository.getMessageCount();
      expect(count, 1);

      final messages = await chatRepository.loadMessages();
      expect(messages.first.content, 'Hello World');
      expect(messages.first.isUser, true);
    });

    test('loadMessages reconciles pending turns as failed', () async {
      await chatRepository.saveMessage(
        ChatMessage(
          content: 'unfinished',
          isUser: true,
          isPending: true,
          timestamp: DateTime.now(),
        ),
      );

      final messages = await chatRepository.loadMessages();

      expect(messages.single.isPending, isFalse);
      expect(messages.single.isFailed, isTrue);
    });

    test(
      'persists failed messages and can mark an existing user message',
      () async {
        final message = ChatMessage(
          content: 'Retry me',
          isUser: true,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
        );

        await chatRepository.saveMessage(message);
        await chatRepository.markMessageFailed(message);

        final stored = await chatRepository.loadMessages();
        expect(stored.single.isFailed, isTrue);
      },
    );

    test(
      'marks the saved row by stable id when duplicate turns exist',
      () async {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(1234);
        final first = ChatMessage(
          content: 'duplicate',
          isUser: true,
          timestamp: timestamp,
        );
        final second = ChatMessage(
          content: 'duplicate',
          isUser: true,
          timestamp: timestamp,
        );

        await chatRepository.saveMessage(first);
        await chatRepository.saveMessage(second);
        await chatRepository.markMessageFailed(first);

        final stored = await chatRepository.loadMessages();
        expect(stored.map((message) => message.isFailed), [true, false]);
      },
    );

    test('clearHistory removes all messages', () async {
      await chatRepository.saveMessage(
        ChatMessage(content: 'Msg 1', isUser: true, timestamp: DateTime.now()),
      );

      await chatRepository.saveMessage(
        ChatMessage(content: 'Msg 2', isUser: false, timestamp: DateTime.now()),
      );

      expect(await chatRepository.getMessageCount(), 2);

      await chatRepository.clearHistory();

      expect(await chatRepository.getMessageCount(), 0);
    });

    test('loadMessages returns messages in chronological order', () async {
      final time1 = DateTime.fromMillisecondsSinceEpoch(1000);
      final time2 = DateTime.fromMillisecondsSinceEpoch(2000);

      await chatRepository.saveMessage(
        ChatMessage(content: 'First', isUser: true, timestamp: time1),
      );

      await chatRepository.saveMessage(
        ChatMessage(content: 'Second', isUser: false, timestamp: time2),
      );

      final messages = await chatRepository.loadMessages();
      expect(messages.length, 2);
      expect(messages[0].content, 'First');
      expect(messages[1].content, 'Second');
    });

    test('saveMessage persists sources and metrics for later reads', () async {
      final message = ChatMessage(
        content: 'Grounded answer',
        isUser: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
        sources: [
          SearchResult(
            id: 'src-1',
            content: 'Source chunk',
            score: 0.75,
            metadata: {'documentTitle': 'Spec'},
          ),
        ],
        metrics: RAGMetrics(
          embeddingTime: const Duration(milliseconds: 10),
          searchTime: const Duration(milliseconds: 20),
          generationTime: const Duration(milliseconds: 30),
          chunksRetrieved: 4,
        ),
      );

      await chatRepository.saveMessage(message);

      final stored = await chatRepository.loadMessages();

      expect(stored.single.sources, hasLength(1));
      expect(stored.single.sources!.single.id, 'src-1');
      expect(stored.single.sources!.single.metadata['documentTitle'], 'Spec');
      expect(
        stored.single.metrics!.embeddingTime,
        const Duration(milliseconds: 10),
      );
      expect(
        stored.single.metrics!.searchTime,
        const Duration(milliseconds: 20),
      );
      expect(
        stored.single.metrics!.generationTime,
        const Duration(milliseconds: 30),
      );
      expect(stored.single.metrics!.chunksRetrieved, 4);
    });

    test('loadMessages respects the provided limit', () async {
      for (var i = 0; i < 3; i++) {
        await chatRepository.saveMessage(
          ChatMessage(
            content: 'message-$i',
            isUser: i.isEven,
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000 + i),
          ),
        );
      }

      final messages = await chatRepository.loadMessages(limit: 2);

      expect(messages.map((message) => message.content), [
        'message-1',
        'message-2',
      ]);
    });

    test('db throws when vector store has not been initialized', () async {
      await vectorStore.close();
      await locator.reset();

      final uninitializedStore = VectorStore();
      locator.registerSingleton<VectorStore>(uninitializedStore);

      final repository = ChatRepository();

      expect(
        () => repository.db,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Database not initialized'),
          ),
        ),
      );
    });
  });
}
