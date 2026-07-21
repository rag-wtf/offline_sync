import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_view.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

class MockRagService extends Mock implements RagService {}

class MockChatRepository extends Mock implements ChatRepository {}

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

class MockSnackbarService extends Mock implements SnackbarService {}

class MockDialogService extends Mock implements DialogService {}

class MockRagSettingsService extends Mock implements RagSettingsService {}

class MockNavigationService extends Mock implements NavigationService {}

class MockVectorStore extends Mock implements VectorStore {}

void main() {
  late MockRagService ragService;
  late MockChatRepository chatRepository;
  late MockDocumentManagementService documentService;
  late MockSnackbarService snackbarService;
  late MockDialogService dialogService;
  late MockRagSettingsService ragSettingsService;
  late MockNavigationService navigationService;

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

    when(
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => ragSettingsService.maxHistoryMessages).thenReturn(10);
    when(
      () => snackbarService.showSnackbar(message: any(named: 'message')),
    ).thenReturn(null);
    when(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async => DialogResponse());
    when(
      () => navigationService.navigateTo<dynamic>(
        Routes.settingsView,
        arguments: any<dynamic>(named: 'arguments'),
        id: any<int?>(named: 'id'),
        preventDuplicates: any<bool>(named: 'preventDuplicates'),
        parameters: any<Map<String, String>?>(named: 'parameters'),
        transition: any<RouteTransitionsBuilder?>(named: 'transition'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => ragService.askWithRAGStream(
        any<String>(),
        includeMetrics: any<bool>(named: 'includeMetrics'),
        conversationHistory: any<List<String>?>(
          named: 'conversationHistory',
        ),
        documentIds: any<List<String>?>(named: 'documentIds'),
      ),
    ).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await locator.reset();
  });

  Widget buildSubject(ChatViewModel viewModel) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatView(
        viewModel: viewModel,
        onViewModelReadyCallback: (_) {},
      ),
    );
  }

  testWidgets('renders loading state and chat input', (tester) async {
    final viewModel = ChatViewModel()..setBusy(true);

    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('renders empty state and navigates to settings', (tester) async {
    final viewModel = ChatViewModel();

    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.text('Start a conversation'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();

    verify(
      () => navigationService.navigateTo<dynamic>(
        Routes.settingsView,
        arguments: any<dynamic>(named: 'arguments'),
        id: any<int?>(named: 'id'),
        preventDuplicates: any<bool>(named: 'preventDuplicates'),
        parameters: any<Map<String, String>?>(named: 'parameters'),
        transition: any<RouteTransitionsBuilder?>(named: 'transition'),
      ),
    ).called(1);
  });

  testWidgets('renders messages, processing progress, and source dialog', (
    tester,
  ) async {
    final source = SearchResult(
      id: 'source-1',
      content: 'Source content',
      score: 0.9,
      metadata: {'documentTitle': 'Manual.pdf'},
    );
    final viewModel = ChatViewModel()
      ..messages.add(
        ChatMessage(
          content: 'Answer',
          isUser: false,
          timestamp: DateTime(2024, 1, 2, 3, 4),
          sources: [source],
        ),
      );

    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.text('Answer'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Manual.pdf'));
    await tester.pump();
    verify(
      () => dialogService.showDialog(
        title: 'Manual.pdf',
        description: 'Source content',
      ),
    ).called(1);

    final saveCompleter = Completer<void>();
    when(
      () => chatRepository.saveMessage(any()),
    ).thenAnswer((_) => saveCompleter.future);
    final sendFuture = viewModel.sendMessage('question');
    await tester.pump();
    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    saveCompleter.complete();
    await sendFuture;
    await tester.pump();
  });

  testWidgets('opens empty document filter dialog and closes it', (
    tester,
  ) async {
    final viewModel = ChatViewModel();

    await tester.pumpWidget(buildSubject(viewModel));
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();

    expect(find.text('No documents available.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('No documents available.'), findsNothing);
  });

  testWidgets('renders filterable documents and toggles selection', (
    tester,
  ) async {
    when(ragService.initialize).thenAnswer((_) async {});
    when(() => chatRepository.loadMessages()).thenAnswer((_) async => []);
    when(() => documentService.getAllDocuments()).thenAnswer(
      (_) async => [
        Document(
          id: 'doc-1',
          title: 'Operations Runbook',
          filePath: '/tmp/runbook.md',
          format: DocumentFormat.plainText,
          chunkCount: 2,
          totalCharacters: 120,
          contentHash: 'hash-1',
          ingestedAt: DateTime(2024),
          status: IngestionStatus.complete,
        ),
      ],
    );
    final viewModel = ChatViewModel();
    await viewModel.initialize();

    await tester.pumpWidget(buildSubject(viewModel));
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Operations Runbook'), findsOneWidget);
    expect(find.text('PLAINTEXT'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(viewModel.selectedDocumentIds, {'doc-1'});
  });

  testWidgets('initializes the view model when no ready callback is supplied', (
    tester,
  ) async {
    when(ragService.initialize).thenAnswer((_) async {});
    when(() => chatRepository.loadMessages()).thenAnswer((_) async => []);
    when(() => documentService.getAllDocuments()).thenAnswer((_) async => []);
    final viewModel = ChatViewModel();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatView(viewModel: viewModel),
      ),
    );
    await tester.pump();

    verify(ragService.initialize).called(1);
    verify(() => chatRepository.loadMessages()).called(1);
  });
}
