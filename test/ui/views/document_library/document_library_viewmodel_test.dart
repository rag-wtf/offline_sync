import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/ui/views/document_library/document_library_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../../helpers/test_helpers.dart';

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

class MockDialogService extends Mock implements DialogService {}

class FakeDocument extends Fake implements Document {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakePlatformFile(name: 'fallback.txt'));
    registerFallbackValue(FakeDocument());
  });

  late MockDocumentManagementService documentService;
  late MockDialogService dialogService;
  late StreamController<IngestionProgress> progressController;
  late Document document;

  setUp(() {
    documentService = MockDocumentManagementService();
    dialogService = MockDialogService();
    progressController = StreamController<IngestionProgress>.broadcast();
    document = Document(
      id: 'doc-1',
      title: 'Quarterly Report',
      filePath: '/tmp/report.pdf',
      format: DocumentFormat.pdf,
      chunkCount: 3,
      totalCharacters: 200,
      contentHash: 'hash',
      ingestedAt: DateTime(2024),
    );

    locator
      ..registerSingleton<DocumentManagementService>(documentService)
      ..registerSingleton<NavigationService>(MockNavigationService())
      ..registerSingleton<DialogService>(dialogService);

    when(documentService.getAllDocuments).thenAnswer((_) async => []);
    when(
      () => documentService.hasSourceForReindex(any()),
    ).thenReturn(true);
    when(
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => progressController.stream);
    when(
      () => dialogService.showConfirmationDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
        confirmationTitle: any(named: 'confirmationTitle'),
      ),
    ).thenAnswer((_) async => DialogResponse());
    when(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).thenAnswer((_) async => DialogResponse());
  });

  tearDown(() async {
    DocumentLibraryViewModel.pickFiles = FilePicker.pickFiles;
    await progressController.close();
    await locator.reset();
  });

  test('dispose cancels ingestion progress listener', () async {
    final viewModel = DocumentLibraryViewModel();
    await viewModel.initialize();

    viewModel.dispose();
    progressController.add(
      const IngestionProgress(
        documentId: 'doc',
        documentTitle: 'Doc',
        stage: 'embedding',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.activeIngestions, isEmpty);
  });

  test('deleteDocument returns false when deletion is not confirmed', () async {
    final viewModel = DocumentLibraryViewModel();

    final deleted = await viewModel.deleteDocument(document);

    expect(deleted, isFalse);
    verifyNever(() => documentService.deleteDocument(any()));
  });

  test('deleteDocument returns true and deletes when confirmed', () async {
    when(
      () => dialogService.showConfirmationDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
        confirmationTitle: any(named: 'confirmationTitle'),
      ),
    ).thenAnswer((_) async => DialogResponse(confirmed: true));
    when(
      () => documentService.deleteDocument(document.id),
    ).thenAnswer((_) async {});

    final viewModel = DocumentLibraryViewModel();

    final deleted = await viewModel.deleteDocument(document);

    expect(deleted, isTrue);
    verify(() => documentService.deleteDocument(document.id)).called(1);
  });

  test('initialize handles progress updates, refreshes'
      ' documents, and shows errors', () async {
    when(documentService.getAllDocuments).thenAnswer((_) async => [document]);

    final viewModel = DocumentLibraryViewModel();
    await viewModel.initialize();

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-1',
        documentTitle: 'Quarterly Report',
        stage: 'embedding',
        currentChunk: 1,
        totalChunks: 2,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.isIngesting, isTrue);
    expect(viewModel.activeIngestions['doc-1']?.stage, 'embedding');

    progressController.add(
      const IngestionProgress(
        documentId: 'doc-1',
        documentTitle: 'Quarterly Report',
        stage: 'error',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    expect(viewModel.documents, [document]);
    expect(viewModel.activeIngestions, isEmpty);
    verify(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).called(1);
  });

  test(
    'initialize removes completed progress and refreshes documents',
    () async {
      when(documentService.getAllDocuments).thenAnswer((_) async => [document]);

      final viewModel = DocumentLibraryViewModel();
      await viewModel.initialize();

      progressController.add(
        const IngestionProgress(
          documentId: 'doc-1',
          documentTitle: 'Quarterly Report',
          stage: 'complete',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.activeIngestions['doc-1']?.stage, 'complete');

      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(viewModel.activeIngestions, isEmpty);
      verifyNever(
        () => dialogService.showDialog(
          title: any(named: 'title'),
          description: any(named: 'description'),
        ),
      );
    },
  );

  test(
    'pickAndIngestFile returns without refreshing when picker is cancelled',
    () async {
      DocumentLibraryViewModel.pickFiles =
          ({required type, required allowedExtensions}) async => [];

      final viewModel = DocumentLibraryViewModel();

      await viewModel.pickAndIngestFile();

      verifyNever(
        () => documentService.addDocumentFromPlatformFile(any<PlatformFile>()),
      );
      verifyNever(documentService.getAllDocuments);
    },
  );

  test(
    'pickAndIngestFile ingests files, shows errors, and refreshes',
    () async {
      final goodFile = FakePlatformFile(
        name: 'good.txt',
        size: 4,
        bytes: Uint8List.fromList([1, 2]),
      );
      final badFile = FakePlatformFile(
        name: 'bad.txt',
        size: 4,
        bytes: Uint8List.fromList([3, 4]),
      );
      DocumentLibraryViewModel.pickFiles =
          ({required type, required allowedExtensions}) async {
            expect(type, FileType.custom);
            expect(allowedExtensions, containsAll(['pdf', 'docx', 'txt']));
            return [goodFile, badFile];
          };
      when(
        () => documentService.addDocumentFromPlatformFile(any<PlatformFile>()),
      ).thenAnswer((_) async => document);
      when(
        () => documentService.addDocumentFromPlatformFile(badFile),
      ).thenThrow(Exception('parse failed'));
      when(documentService.getAllDocuments).thenAnswer((_) async => [document]);

      final viewModel = DocumentLibraryViewModel();

      await viewModel.pickAndIngestFile();

      verify(
        () => documentService.addDocumentFromPlatformFile(goodFile),
      ).called(1);
      verify(
        () => documentService.addDocumentFromPlatformFile(badFile),
      ).called(1);
      verify(documentService.getAllDocuments).called(1);
      verify(
        () => dialogService.showDialog(
          title: any(named: 'title'),
          description: any(named: 'description'),
        ),
      ).called(1);
    },
  );

  test('showDocumentDetails navigates to document detail', () async {
    final navigationService =
        locator<NavigationService>() as MockNavigationService;
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

    final viewModel = DocumentLibraryViewModel();

    await viewModel.showDocumentDetails(document);

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
  });

  test('identifies documents embedded with a different model', () async {
    final settings = getAndRegisterMockRagSettingsService();
    when(() => settings.activeEmbeddingModelId).thenReturn('active-model');
    final mismatched = Document(
      id: 'mismatch',
      title: 'Mismatch',
      filePath: '/tmp/mismatch.txt',
      format: DocumentFormat.plainText,
      chunkCount: 1,
      totalCharacters: 1,
      contentHash: 'hash',
      ingestedAt: DateTime(2024),
      status: IngestionStatus.complete,
      embeddingModelId: 'old-model',
    );
    final viewModel = DocumentLibraryViewModel(
      settingsService: settings,
    );

    expect(viewModel.needsReindex(mismatched), isTrue);
  });

  test('marks indexed documents as unavailable when no embedder is active', () {
    final settings = getAndRegisterMockRagSettingsService();
    when(() => settings.activeEmbeddingModelId).thenReturn(null);
    final indexed = Document(
      id: document.id,
      title: document.title,
      filePath: document.filePath,
      format: document.format,
      chunkCount: document.chunkCount,
      totalCharacters: document.totalCharacters,
      contentHash: document.contentHash,
      ingestedAt: document.ingestedAt,
      status: IngestionStatus.complete,
      embeddingModelId: 'gecko-64',
    );

    final viewModel = DocumentLibraryViewModel(settingsService: settings);

    expect(viewModel.needsReindex(indexed), isTrue);
  });

  test(
    'reindex action uses the ingestion pipeline and refreshes state',
    () async {
      when(
        () => documentService.reindexDocument(document.id),
      ).thenAnswer((_) async => document);
      when(documentService.getAllDocuments).thenAnswer((_) async => [document]);

      final viewModel = DocumentLibraryViewModel();
      await viewModel.reindexDocument(document);

      verify(() => documentService.reindexDocument(document.id)).called(1);
      verify(documentService.getAllDocuments).called(1);
    },
  );

  test('reports unavailable and failed reindex operations', () async {
    when(
      () => documentService.hasSourceForReindex(document),
    ).thenReturn(false);
    final viewModel = DocumentLibraryViewModel();

    expect(await viewModel.reindexDocument(document), isFalse);
    verify(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).called(1);

    when(
      () => documentService.hasSourceForReindex(document),
    ).thenReturn(true);
    when(
      () => documentService.reindexDocument(document.id),
    ).thenThrow(StateError('reindex failed'));
    expect(await viewModel.reindexDocument(document), isFalse);

    when(
      () => documentService.renameDocument(document.id, 'Renamed'),
    ).thenThrow(StateError('rename failed'));
    await viewModel.renameDocument(document, 'Renamed');
    verify(
      () => dialogService.showDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
      ),
    ).called(2);
  });
}
