import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/ui/views/document_library/document_library_view.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../../helpers/test_helpers.dart';

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

class MockDialogService extends Mock implements DialogService {}

Document _buildDocument({
  required String id,
  required String title,
  required DocumentFormat format,
  required IngestionStatus status,
  String? errorMessage,
}) {
  return Document(
    id: id,
    title: title,
    filePath: '/tmp/$id',
    format: format,
    chunkCount: 3,
    totalCharacters: 500,
    contentHash: 'hash-$id',
    ingestedAt: DateTime(2024, 1, 2),
    status: status,
    errorMessage: errorMessage,
    embeddingModelId: 'gecko-64',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakePlatformFile(name: 'fallback.txt'));
    registerFallbackValue(
      Document(
        id: 'fallback',
        title: 'fallback',
        filePath: 'fallback.txt',
        format: DocumentFormat.plainText,
        chunkCount: 0,
        totalCharacters: 0,
        contentHash: 'fallback-hash',
        ingestedAt: DateTime(2024),
      ),
    );
  });

  late MockDocumentManagementService documentService;
  late MockNavigationService navigationService;
  late MockDialogService dialogService;
  late StreamController<IngestionProgress> progressController;
  late Document document;

  setUp(() {
    documentService = MockDocumentManagementService();
    navigationService = MockNavigationService();
    dialogService = MockDialogService();
    progressController = StreamController<IngestionProgress>.broadcast();
    document = Document(
      id: 'doc-1',
      title: 'Quarterly Report',
      filePath: '/tmp/report.pdf',
      format: DocumentFormat.pdf,
      chunkCount: 3,
      totalCharacters: 500,
      contentHash: 'hash',
      ingestedAt: DateTime(2024, 1, 2),
      status: IngestionStatus.error,
      errorMessage: 'Embedding failed',
    );

    locator
      ..registerSingleton<DocumentManagementService>(documentService)
      ..registerSingleton<NavigationService>(navigationService)
      ..registerSingleton<DialogService>(dialogService);
    getAndRegisterMockRagSettingsService();

    when(
      () => navigationService.navigateTo<dynamic>(
        any<String>(),
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => dialogService.showConfirmationDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
        confirmationTitle: any(named: 'confirmationTitle'),
      ),
    ).thenAnswer((_) async => DialogResponse(confirmed: true));
    when(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async => DialogResponse());
    when(
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => progressController.stream);
    when(
      () => documentService.hasSourceForReindex(any<Document>()),
    ).thenReturn(false);
    when(() => documentService.deleteDocument(any())).thenAnswer((_) async {});
    when(
      () => documentService.addDocumentFromPlatformFile(any()),
    ).thenAnswer((_) async => document);
  });

  tearDown(() async {
    await progressController.close();
    await unregisterTestHelpers();
  });

  testWidgets('shows loading state before initialization completes', (
    tester,
  ) async {
    final completer = Completer<List<Document>>();
    when(
      () => documentService.getAllDocuments(),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentLibraryView(),
      ),
    );
    await tester.pump();

    expect(find.text('Loading documents...'), findsOneWidget);

    completer.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('shows empty state when there are no documents', (tester) async {
    when(() => documentService.getAllDocuments()).thenAnswer((_) async => []);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentLibraryView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No documents yet'), findsOneWidget);
    expect(find.text('Tap the button below to get started'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add Document'),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders documents, progress cards, navigation, and delete flow',
    (tester) async {
      when(
        () => documentService.getAllDocuments(),
      ).thenAnswer((_) async => [document]);

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentLibraryView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Knowledge Base'), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
      expect(find.text('Failed'), findsWidgets);
      expect(find.text('Embedding failed'), findsOneWidget);

      progressController.add(
        const IngestionProgress(
          documentId: 'doc-1',
          documentTitle: 'Quarterly Report',
          stage: 'embedding',
          currentChunk: 1,
          totalChunks: 3,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Generating embeddings...', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('1/3 chunks', skipOffstage: false), findsOneWidget);

      await tester.tap(find.byType(Dismissible).first);
      await tester.pump();
      verify(
        () => navigationService.navigateTo<dynamic>(
          Routes.documentDetailView,
          arguments: any<dynamic>(named: 'arguments'),
          id: any(named: 'id'),
          preventDuplicates: any(named: 'preventDuplicates'),
          parameters: any(named: 'parameters'),
          transition: any(named: 'transition'),
        ),
      ).called(1);

      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      verify(() => documentService.deleteDocument(document.id)).called(1);
    },
  );

  testWidgets('renders every document status and format branch', (
    tester,
  ) async {
    final documents = [
      _buildDocument(
        id: 'pdf-error',
        title: 'PDF Error',
        format: DocumentFormat.pdf,
        status: IngestionStatus.error,
        errorMessage: 'Embedding failed',
      ),
      _buildDocument(
        id: 'docx-pending',
        title: 'DOCX Pending',
        format: DocumentFormat.docx,
        status: IngestionStatus.pending,
      ),
      _buildDocument(
        id: 'epub-processing',
        title: 'EPUB Processing',
        format: DocumentFormat.epub,
        status: IngestionStatus.processing,
      ),
      _buildDocument(
        id: 'markdown-ready',
        title: 'Markdown Ready',
        format: DocumentFormat.markdown,
        status: IngestionStatus.complete,
      ),
      _buildDocument(
        id: 'text-cancelled',
        title: 'Text Cancelled',
        format: DocumentFormat.plainText,
        status: IngestionStatus.cancelled,
      ),
      _buildDocument(
        id: 'unknown-cancelled',
        title: 'Unknown Cancelled',
        format: DocumentFormat.unknown,
        status: IngestionStatus.cancelled,
      ),
    ];
    when(
      () => documentService.getAllDocuments(),
    ).thenAnswer((_) async => documents);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentLibraryView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('Cancelled'), findsNWidgets(2));

    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
    expect(find.byIcon(Icons.description_rounded), findsOneWidget);
    expect(find.byIcon(Icons.book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.code_rounded), findsOneWidget);
    expect(find.byIcon(Icons.article_rounded), findsNWidgets(2));
  });

  testWidgets('renders non-embedding ingestion progress states', (
    tester,
  ) async {
    when(
      () => documentService.getAllDocuments(),
    ).thenAnswer((_) async => [document]);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentLibraryView(),
      ),
    );
    await tester.pumpAndSettle();

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-context',
        documentTitle: 'Context Document',
        stage: 'contextualizing',
        currentChunk: 2,
        totalChunks: 4,
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(
      find.text('Contextualizing...', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('2/4 chunks', skipOffstage: false), findsOneWidget);

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-complete',
        documentTitle: 'Completed Document',
        stage: 'complete',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('Complete!', skipOffstage: false), findsOneWidget);

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-error',
        documentTitle: 'Errored Document',
        stage: 'error',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('Errored Document', skipOffstage: false), findsOneWidget);

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-other',
        documentTitle: 'Other Document',
        stage: 'other',
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('Processing...', skipOffstage: false), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('uses the custom onViewModelReady callback when provided', (
    tester,
  ) async {
    when(() => documentService.getAllDocuments()).thenAnswer((_) async => []);
    final callbackViewModels = <Object?>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentLibraryView(
          onViewModelReadyCallback: callbackViewModels.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(callbackViewModels, hasLength(1));
    verifyNever(() => documentService.getAllDocuments());
  });
}
