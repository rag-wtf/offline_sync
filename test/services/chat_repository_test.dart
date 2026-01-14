import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Mock PathProvider
class MockPathProviderPlatform extends PathProviderPlatform {
  final Directory tempDir;

  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
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

      chatRepository = ChatRepository();
      chatRepository.initialize();
    });

    tearDown(() async {
      vectorStore.close();
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

    test('clearHistory removes all messages', () async {
      await chatRepository.saveMessage(ChatMessage(
        content: 'Msg 1',
        isUser: true,
        timestamp: DateTime.now(),
      ));

      await chatRepository.saveMessage(ChatMessage(
        content: 'Msg 2',
        isUser: false,
        timestamp: DateTime.now(),
      ));

      expect(await chatRepository.getMessageCount(), 2);

      await chatRepository.clearHistory();

      expect(await chatRepository.getMessageCount(), 0);
    });

    test('loadMessages returns messages in chronological order', () async {
       final time1 = DateTime.fromMillisecondsSinceEpoch(1000);
       final time2 = DateTime.fromMillisecondsSinceEpoch(2000);

       await chatRepository.saveMessage(ChatMessage(
         content: 'First',
         isUser: true,
         timestamp: time1,
       ));

       await chatRepository.saveMessage(ChatMessage(
         content: 'Second',
         isUser: false,
         timestamp: time2,
       ));

       final messages = await chatRepository.loadMessages();
       expect(messages.length, 2);
       expect(messages[0].content, 'First');
       expect(messages[1].content, 'Second');
    });
  });
}
