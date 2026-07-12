import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/ui/views/document_library/document_library_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../../helpers/test_helpers.dart';

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

class MockDialogService extends Mock implements DialogService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      () => documentService.ingestionProgressStream,
    ).thenAnswer((_) => progressController.stream);
    when(
      () => dialogService.showConfirmationDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
        confirmationTitle: any(named: 'confirmationTitle'),
      ),
    ).thenAnswer(
      (_) async => DialogResponse(),
    );
  });

  tearDown(() async {
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
    ).thenAnswer(
      (_) async => DialogResponse(confirmed: true),
    );
    when(() => documentService.deleteDocument(document.id)).thenAnswer(
      (_) async {},
    );

    final viewModel = DocumentLibraryViewModel();

    final deleted = await viewModel.deleteDocument(document);

    expect(deleted, isTrue);
    verify(() => documentService.deleteDocument(document.id)).called(1);
  });
}
