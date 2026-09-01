import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/exceptions.dart';
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
  late MockSnackbarService snackbarService;
  late MockDialogService dialogService;
  late MockRagSettingsService ragSettingsService;
  late MockNavigationService navigationService;

  setUpAll(() {
    registerFallbackValue(const SizedBox.shrink());
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
    snackbarService = MockSnackbarService();
    dialogService = MockDialogService();
    ragSettingsService = MockRagSettingsService();
    navigationService = MockNavigationService();

    locator
      ..registerSingleton<RagService>(ragService)
      ..registerSingleton<ChatRepository>(chatRepository)
      ..registerSingleton<DocumentManagementService>(documentService)
      ..registerSingleton<RagSettingsService>(ragSettingsService)
      ..registerSingleton<VectorStore>(MockVectorStore())
      ..registerSingleton<SnackbarService>(snackbarService)
      ..registerSingleton<NavigationService>(navigationService)
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
    when(
      () => snackbarService.showSnackbar(
        message: any(named: 'message'),
        duration: any(named: 'duration'),
      ),
    ).thenReturn(null);
    when(
      () => navigationService.navigateWithTransition<bool?>(
        any(),
        transitionStyle: any(named: 'transitionStyle'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => navigationService.navigateTo<dynamic>(
        Routes.settingsView,
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).thenAnswer((_) async => null);
  });

  tearDown(() async {
    ChatViewModel.pickFiles = FilePicker.pickFiles;
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

    expect(invocation, ['AI: second', 'User: third']);
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

  test('initialize keeps only completed documents and'
      ' enables scroll for history', () async {
    final progressController = StreamController<IngestionProgress>.broadcast();
    when(ragService.initialize).thenAnswer((_) async {});
    when(() => chatRepository.loadMessages()).thenAnswer(
      (_) async => [
        ChatMessage(
          content: 'persisted',
          isUser: true,
          timestamp: DateTime(2024, 1, 1, 8),
        ),
      ],
    );
    when(
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => progressController.stream);
    when(() => documentService.getAllDocuments()).thenAnswer(
      (_) async => [
        Document(
          id: 'done',
          title: 'Done',
          filePath: '/tmp/done.txt',
          format: DocumentFormat.plainText,
          chunkCount: 1,
          totalCharacters: 100,
          contentHash: 'hash-1',
          ingestedAt: DateTime(2024),
          status: IngestionStatus.complete,
        ),
        Document(
          id: 'processing',
          title: 'Processing',
          filePath: '/tmp/progress.txt',
          format: DocumentFormat.plainText,
          chunkCount: 1,
          totalCharacters: 100,
          contentHash: 'hash-2',
          ingestedAt: DateTime(2024),
          status: IngestionStatus.processing,
        ),
      ],
    );

    final viewModel = ChatViewModel();
    await viewModel.initialize();

    expect(viewModel.messages, hasLength(1));
    expect(viewModel.availableDocuments.map((doc) => doc.id), ['done']);
    expect(viewModel.shouldScroll, isTrue);

    await progressController.close();
  });

  test('initialize refreshes documents again'
      ' when ingestion completes', () async {
    final progressController = StreamController<IngestionProgress>.broadcast();
    when(ragService.initialize).thenAnswer((_) async {});
    when(() => chatRepository.loadMessages()).thenAnswer((_) async => []);
    when(
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => progressController.stream);
    when(() => documentService.getAllDocuments()).thenAnswer((_) async => []);

    final viewModel = ChatViewModel();
    await viewModel.initialize();

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-1',
        documentTitle: 'Doc',
        stage: 'complete',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    verify(
      () => documentService.getAllDocuments(),
    ).called(greaterThanOrEqualTo(2));
    await progressController.close();
  });

  test('initialize shows snackbar when startup fails', () async {
    when(ragService.initialize).thenThrow(Exception('bootstrap failed'));

    final viewModel = ChatViewModel();
    await viewModel.initialize();

    verify(
      () => snackbarService.showSnackbar(
        message: 'Initialization error: Exception: bootstrap failed',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('toggleDocumentSelection toggles filters and'
      ' onScrolled clears pending scroll', () {
    final viewModel = ChatViewModel()..toggleDocumentSelection('doc-1');
    expect(viewModel.selectedDocumentIds, {'doc-1'});

    viewModel.toggleDocumentSelection('doc-1');
    expect(viewModel.selectedDocumentIds, isEmpty);

    viewModel
      ..sendMessage('   ').ignore()
      ..onScrolled();

    expect(viewModel.shouldScroll, isFalse);
  });

  test('sendMessage streams metadata and tokens into'
      ' the persisted assistant reply', () async {
    final savedMessages = <ChatMessage>[];
    when(() => chatRepository.saveMessage(any())).thenAnswer((
      invocation,
    ) async {
      savedMessages.add(invocation.positionalArguments.first as ChatMessage);
    });
    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer(
      (_) => Stream<RAGStreamEvent>.fromIterable([
        RAGMetadataEvent(
          sources: [
            SearchResult(
              id: 'source-1',
              content: 'Supporting chunk',
              score: 0.9,
              metadata: {'documentTitle': 'Manual'},
            ),
          ],
          metrics: RAGMetrics(
            embeddingTime: const Duration(milliseconds: 3),
            searchTime: const Duration(milliseconds: 4),
            generationTime: const Duration(milliseconds: 5),
            chunksRetrieved: 1,
          ),
        ),
        RAGTokenEvent('Hello'),
        RAGTokenEvent(' world'),
        RAGCompleteEvent(),
      ]),
    );

    final viewModel = ChatViewModel()..toggleDocumentSelection('doc-7');

    await viewModel.sendMessage('question');

    expect(viewModel.messages, hasLength(2));
    expect(viewModel.messages.last.content, 'Hello world');
    expect(viewModel.messages.last.sources!.single.id, 'source-1');
    expect(viewModel.messages.last.metrics!.chunksRetrieved, 1);
    expect(savedMessages, hasLength(2));
    expect(savedMessages.last.content, 'Hello world');

    final documentIds =
        verify(
              () => ragService.askWithRAGStream(
                'question',
                includeMetrics: true,
                conversationHistory: any(named: 'conversationHistory'),
                documentIds: captureAny(named: 'documentIds'),
              ),
            ).captured.single
            as List<String>;
    expect(documentIds, ['doc-7']);
  });

  test('sendMessage prompts for auth when'
      ' generation requires authentication', () async {
    when(() => chatRepository.saveMessage(any())).thenAnswer((_) async {});
    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer(
      (_) => Stream<RAGStreamEvent>.error(
        AuthenticationRequiredException('token missing'),
      ),
    );

    final viewModel = ChatViewModel();
    await viewModel.sendMessage('needs auth');

    expect(viewModel.messages, hasLength(1));
    expect(viewModel.messages.single.content, 'needs auth');
    verify(
      () => navigationService.navigateWithTransition<bool?>(
        any(),
        transitionStyle: Transition.fade,
      ),
    ).called(1);
    verify(
      () => snackbarService.showSnackbar(
        message: 'Please provide authentication and try again',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('sendMessage removes placeholder and shows generic error', () async {
    when(() => chatRepository.saveMessage(any())).thenAnswer((_) async {});
    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer(
      (_) => Stream<RAGStreamEvent>.error(Exception('network down')),
    );

    final viewModel = ChatViewModel();

    await viewModel.sendMessage('question');

    expect(viewModel.messages, hasLength(1));
    expect(viewModel.messages.single.content, 'question');
    verify(
      () => snackbarService.showSnackbar(
        message: 'Error: Exception: network down',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('pickAndIngestFiles returns when picker is cancelled', () async {
    ChatViewModel.pickFiles =
        ({required type, required allowedExtensions}) async => [];

    final viewModel = ChatViewModel();
    await viewModel.pickAndIngestFiles();

    verifyNever(() => documentService.addMultipleDocuments(any()));
    expect(viewModel.isBusy, isFalse);
  });

  test('pickAndIngestFiles returns when picked files have no paths', () async {
    ChatViewModel.pickFiles =
        ({required type, required allowedExtensions}) async => [
          FakePlatformFile(
            name: 'bytes-only.txt',
            size: 2,
            bytes: Uint8List.fromList([1, 2]),
          ),
        ];

    final viewModel = ChatViewModel();
    await viewModel.pickAndIngestFiles();

    verifyNever(() => documentService.addMultipleDocuments(any()));
    expect(viewModel.isBusy, isFalse);
  });

  test('pickAndIngestFiles reports complete failure counts', () async {
    ChatViewModel.pickFiles =
        ({required type, required allowedExtensions}) async => [
          FakePlatformFile(name: 'first.txt', size: 1, path: '/tmp/first.txt'),
          FakePlatformFile(
            name: 'second.txt',
            size: 1,
            path: '/tmp/second.txt',
          ),
        ];
    when(() => documentService.addMultipleDocuments(any())).thenAnswer(
      (_) async => const IngestionResult(
        succeeded: [],
        failed: {
          '/tmp/first.txt': 'parse failed',
          '/tmp/second.txt': 'parse failed',
        },
      ),
    );

    final viewModel = ChatViewModel();
    await viewModel.pickAndIngestFiles();

    verify(
      () => snackbarService.showSnackbar(
        message: 'Failed to ingest 2 file(s)',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('pickAndIngestFiles reports partial'
      ' failures and full success', () async {
    ChatViewModel.pickFiles =
        ({required type, required allowedExtensions}) async => [
          FakePlatformFile(name: 'first.txt', size: 1, path: '/tmp/first.txt'),
          FakePlatformFile(
            name: 'second.txt',
            size: 1,
            path: '/tmp/second.txt',
          ),
        ];
    final succeededDoc = Document(
      id: 'doc-1',
      title: 'First',
      filePath: '/tmp/first.txt',
      format: DocumentFormat.plainText,
      chunkCount: 1,
      totalCharacters: 10,
      contentHash: 'hash-1',
      ingestedAt: DateTime(2024),
    );
    when(() => documentService.addMultipleDocuments(any())).thenAnswer(
      (_) async => IngestionResult(
        succeeded: [succeededDoc],
        failed: {'/tmp/second.txt': 'parse failed'},
      ),
    );

    final viewModel = ChatViewModel();
    await viewModel.pickAndIngestFiles();

    verify(
      () => snackbarService.showSnackbar(
        message: 'Ingested 1 file(s). Failed to ingest 1 file(s).',
        duration: any(named: 'duration'),
      ),
    ).called(1);

    when(() => documentService.addMultipleDocuments(any())).thenAnswer(
      (_) async => IngestionResult(
        succeeded: [succeededDoc, succeededDoc],
        failed: const {},
      ),
    );

    await viewModel.pickAndIngestFiles();

    verify(
      () => snackbarService.showSnackbar(
        message: 'Successfully ingested 2 file(s)',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('pickAndIngestFiles reports ingestion exceptions', () async {
    ChatViewModel.pickFiles =
        ({required type, required allowedExtensions}) async => [
          FakePlatformFile(name: 'first.txt', size: 1, path: '/tmp/first.txt'),
        ];
    when(
      () => documentService.addMultipleDocuments(any()),
    ).thenThrow(Exception('disk full'));

    final viewModel = ChatViewModel();
    await viewModel.pickAndIngestFiles();

    verify(
      () => snackbarService.showSnackbar(
        message: 'Ingestion error: Exception: disk full',
        duration: any(named: 'duration'),
      ),
    ).called(1);
    expect(viewModel.isBusy, isFalse);
  });

  test('navigateToSettings delegates to the'
      ' generated settings route', () async {
    final viewModel = ChatViewModel();

    await viewModel.navigateToSettings();

    verify(
      () => navigationService.navigateTo<dynamic>(
        Routes.settingsView,
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).called(1);
  });

  test('sendMessage prompts for authentication'
      ' when the stream requires it', () async {
    when(() => chatRepository.saveMessage(any())).thenAnswer((_) async {});
    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer(
      (_) => Stream<RAGStreamEvent>.error(AuthenticationRequiredException()),
    );

    final viewModel = ChatViewModel();
    await viewModel.sendMessage('needs auth');

    expect(viewModel.messages, hasLength(1));
    expect(viewModel.messages.single.content, 'needs auth');
    verify(
      () => navigationService.navigateWithTransition<bool?>(
        any(),
        transitionStyle: Transition.fade,
      ),
    ).called(1);
    verify(
      () => snackbarService.showSnackbar(
        message: 'Please provide authentication and try again',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('sendMessage reports stream failures and'
      ' clears processing state', () async {
    when(() => chatRepository.saveMessage(any())).thenAnswer((_) async {});
    when(
      () => ragService.askWithRAGStream(
        any(),
        includeMetrics: any(named: 'includeMetrics'),
        conversationHistory: any(named: 'conversationHistory'),
        documentIds: any(named: 'documentIds'),
      ),
    ).thenAnswer(
      (_) => Stream<RAGStreamEvent>.error(Exception('model offline')),
    );

    final viewModel = ChatViewModel();
    await viewModel.sendMessage('question');

    expect(viewModel.isProcessing, isFalse);
    expect(viewModel.messages, hasLength(1));
    verify(
      () => snackbarService.showSnackbar(
        message: 'Error: Exception: model offline',
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  test('navigateToSettings delegates to the navigation service', () async {
    final viewModel = ChatViewModel();

    await viewModel.navigateToSettings();

    verify(
      () => navigationService.navigateTo<dynamic>(
        Routes.settingsView,
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).called(1);
  });
}
