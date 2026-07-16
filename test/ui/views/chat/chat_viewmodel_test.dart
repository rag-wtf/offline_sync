import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../../helpers/test_helpers.dart';

class MockRagService extends Mock implements RagService {}

class MockChatRepository extends Mock implements ChatRepository {}

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

class MockSnackbarService extends Mock implements SnackbarService {}

class MockDialogService extends Mock implements DialogService {}

class MockRagSettingsService extends Mock implements RagSettingsService {}

void main() {
  late MockRagService ragService;
  late MockChatRepository chatRepository;
  late MockDocumentManagementService documentService;
  late MockDialogService dialogService;
  late MockRagSettingsService ragSettingsService;

  setUpAll(() {
    registerFallbackValue(
      ChatMessage(
        content: '',
        isUser: true,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  });

  setUp(() {
    ragService = MockRagService();
    chatRepository = MockChatRepository();
    documentService = MockDocumentManagementService();
    dialogService = MockDialogService();
    ragSettingsService = MockRagSettingsService();

    locator
      ..registerSingleton<RagService>(ragService)
      ..registerSingleton<ChatRepository>(chatRepository)
      ..registerSingleton<DocumentManagementService>(documentService)
      ..registerSingleton<RagSettingsService>(ragSettingsService)
      ..registerSingleton<VectorStore>(MockVectorStore())
      ..registerSingleton<SnackbarService>(MockSnackbarService())
      ..registerSingleton<NavigationService>(MockNavigationService())
      ..registerSingleton<DialogService>(dialogService);

    when(() => ragSettingsService.maxHistoryMessages).thenReturn(2);
    when(() => documentService.getAllDocuments()).thenAnswer((_) async => []);
    when(
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async => DialogResponse());
  });

  tearDown(() async {
    await locator.reset();
  });

  test('sendMessage marks processing before first await', () async {
    final saveCompleter = Completer<void>();
    when(
      () => chatRepository.saveMessage(any()),
    ).thenAnswer((_) => saveCompleter.future);

    final viewModel = ChatViewModel();

    final firstSend = viewModel.sendMessage('hello');
    await Future<void>.delayed(Duration.zero);
    final secondSend = viewModel.sendMessage('hello again');

    expect(viewModel.isProcessing, isTrue);
    verify(() => chatRepository.saveMessage(any())).called(1);

    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer((_) => Stream<RAGStreamEvent>.value(RAGCompleteEvent()));

    saveCompleter.complete();
    await Future.wait([firstSend, secondSend]);
  });

  test('sendMessage uses configured history cap', () async {
    final savedMessages = <ChatMessage>[];
    when(() => chatRepository.loadMessages()).thenAnswer(
      (_) async => [
        ChatMessage(
          content: 'first',
          isUser: true,
          timestamp: DateTime(2024, 1, 1, 9),
        ),
        ChatMessage(
          content: 'second',
          isUser: false,
          timestamp: DateTime(2024, 1, 1, 10),
        ),
        ChatMessage(
          content: 'third',
          isUser: true,
          timestamp: DateTime(2024, 1, 1, 11),
        ),
      ],
    );
    when(() => chatRepository.saveMessage(any())).thenAnswer((
      invocation,
    ) async {
      savedMessages.add(invocation.positionalArguments.first as ChatMessage);
    });
    when(ragService.initialize).thenAnswer((_) async {});
    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer((_) => Stream<RAGStreamEvent>.value(RAGCompleteEvent()));

    final viewModel = ChatViewModel();
    await viewModel.initialize();
    await viewModel.sendMessage('hello');

    final invocation =
        verify(
              () => ragService.askWithRAGStream(
                'hello',
                includeMetrics: true,
                conversationHistory: captureAny(named: 'conversationHistory'),
                documentIds: any(named: 'documentIds'),
              ),
            ).captured.single
            as List<String>;

    expect(invocation, [
      'User: third',
      'User: hello',
    ]);
    expect(savedMessages, isNotEmpty);
  });

  test('showSourceDetail opens dialog even without documentId', () async {
    final viewModel = ChatViewModel();
    final source = SearchResult(
      id: 'src-1',
      content: 'Chunk content',
      score: 0.9,
      metadata: {'documentTitle': 'Imported bytes'},
    );

    await viewModel.showSourceDetail(source);

    verify(
      () => dialogService.showDialog(
        title: 'Imported bytes',
        description: 'Chunk content',
      ),
    ).called(1);
  });
}
