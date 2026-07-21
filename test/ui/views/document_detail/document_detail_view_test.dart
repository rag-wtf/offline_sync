import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/document_detail/document_detail_view.dart';

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

void main() {
  late MockDocumentManagementService documentService;
  late Document document;
  late EmbeddingData chunk;

  setUp(() {
    documentService = MockDocumentManagementService();
    document = Document(
      id: 'doc-1',
      title: 'Design Notes',
      filePath: '/tmp/design.md',
      format: DocumentFormat.markdown,
      chunkCount: 1,
      totalCharacters: 128,
      contentHash: 'hash',
      ingestedAt: DateTime(2024, 1, 3),
      status: IngestionStatus.complete,
    );
    chunk = EmbeddingData(
      id: 'chunk-1',
      documentId: 'doc-1',
      content: 'Chunk body',
      embedding: const [0.1, 0.2],
      metadata: const {'page': 1},
    );

    locator.registerSingleton<DocumentManagementService>(documentService);
  });

  tearDown(locator.reset);

  testWidgets('shows loading state while chunks are fetched', (tester) async {
    final completer = Completer<List<EmbeddingData>>();
    when(() => documentService.getDocumentChunks(document.id)).thenAnswer(
      (_) => completer.future,
    );

    await tester.pumpWidget(
      MaterialApp(home: DocumentDetailView(document: document)),
    );
    await tester.pump();

    expect(find.text('Loading chunks...'), findsOneWidget);

    completer.complete([]);
    await tester.pumpAndSettle();
  });

  testWidgets('renders empty state when the document has no chunks', (
    tester,
  ) async {
    when(() => documentService.getDocumentChunks(document.id)).thenAnswer(
      (_) async => [],
    );

    await tester.pumpWidget(
      MaterialApp(home: DocumentDetailView(document: document)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No chunks found'), findsOneWidget);
    expect(find.text('/tmp/design.md'), findsOneWidget);
  });

  testWidgets('renders chunk details and metadata when chunks exist', (
    tester,
  ) async {
    when(() => documentService.getDocumentChunks(document.id)).thenAnswer(
      (_) async => [chunk],
    );

    await tester.pumpWidget(
      MaterialApp(home: DocumentDetailView(document: document)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chunk 1'), findsOneWidget);
    expect(find.text('Design Notes'), findsOneWidget);

    await tester.tap(find.text('Chunk 1'));
    await tester.pumpAndSettle();

    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(find.text('Chunk body'), findsWidgets);
    expect(find.text('{page: 1}'), findsOneWidget);
  });

  testWidgets('uses the custom onViewModelReady callback when provided', (
    tester,
  ) async {
    final callbackViewModels = <Object?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentDetailView(
          document: document,
          onViewModelReadyCallback: callbackViewModels.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(callbackViewModels, hasLength(1));
    verifyNever(() => documentService.getDocumentChunks(any()));
  });
}
