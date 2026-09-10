import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_viewmodel.dart';
import 'package:offline_sync/ui/views/chat/widgets/chat_message_tile.dart';

void main() {
  Widget buildSubject(
    ChatMessage message, {
    void Function(SearchResult)? onSourceClick,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatMessageTile(message: message, onSourceClick: onSourceClick),
      ),
    );
  }

  testWidgets('renders a user message aligned to the end', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        ChatMessage(
          content: 'Hello from me',
          isUser: true,
          timestamp: DateTime(2024, 1, 2, 3, 4),
        ),
      ),
    );

    expect(find.text('Hello from me'), findsOneWidget);
    expect(find.text('03:04'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Column &&
            widget.crossAxisAlignment == CrossAxisAlignment.end,
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders a streaming assistant message with cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        ChatMessage(
          content: '',
          isUser: false,
          timestamp: DateTime(2024, 1, 2, 3, 4),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ChatMessageTile),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    expect(find.text('03:04'), findsOneWidget);
  });

  testWidgets(
    'renders source chips with chunk content and sends clicks to callback',
    (tester) async {
      SearchResult? selectedSource;
      final source = SearchResult(
        id: 'source-1',
        content: 'Relevant context',
        score: 0.8,
        metadata: {'documentTitle': 'Guide.pdf'},
      );

      await tester.pumpWidget(
        buildSubject(
          ChatMessage(
            content: 'Answer',
            isUser: false,
            timestamp: DateTime(2024, 1, 2, 3, 4),
            sources: [source],
          ),
          onSourceClick: (value) => selectedSource = value,
        ),
      );

      expect(find.text('Sources'), findsOneWidget);
      expect(
        find.widgetWithText(ActionChip, 'Relevant context'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ActionChip, 'Relevant context'));
      await tester.pump();

      expect(selectedSource, same(source));
    },
  );

  testWidgets('uses fallback source title when content is blank and tolerates '
      'absent callback', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        ChatMessage(
          content: 'Answer',
          isUser: false,
          timestamp: DateTime(2024, 1, 2, 3, 4),
          sources: [
            SearchResult(
              id: 'source-2',
              content: '   ',
              score: 0.7,
              metadata: const {},
            ),
          ],
        ),
      ),
    );

    expect(find.widgetWithText(ActionChip, 'Source'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Source'));
    await tester.pump();
  });

  testWidgets(
    'renders multiple distinct chunks from the same document as separate chips',
    (tester) async {
      final chunk1 = SearchResult(
        id: 'chunk-1',
        content: 'First chunk content',
        score: 0.9,
        metadata: {'documentId': 'doc-1', 'documentTitle': 'Report.pdf'},
      );
      final chunk2 = SearchResult(
        id: 'chunk-2',
        content: 'Second chunk content',
        score: 0.85,
        metadata: {'documentId': 'doc-1', 'documentTitle': 'Report.pdf'},
      );

      await tester.pumpWidget(
        buildSubject(
          ChatMessage(
            content: 'Answer based on multiple chunks',
            isUser: false,
            timestamp: DateTime(2024, 1, 2, 3, 4),
            sources: [chunk1, chunk2],
          ),
        ),
      );

      expect(
        find.widgetWithText(ActionChip, 'First chunk content'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ActionChip, 'Second chunk content'),
        findsOneWidget,
      );
    },
  );

  testWidgets('deduplicates identical duplicate chunks', (tester) async {
    final chunk1 = SearchResult(
      id: 'chunk-dup',
      content: 'Repeated content',
      score: 0.9,
      metadata: {'documentId': 'doc-1'},
    );
    final chunk2 = SearchResult(
      id: 'chunk-dup',
      content: 'Repeated content',
      score: 0.88,
      metadata: {'documentId': 'doc-1'},
    );

    await tester.pumpWidget(
      buildSubject(
        ChatMessage(
          content: 'Answer',
          isUser: false,
          timestamp: DateTime(2024, 1, 2, 3, 4),
          sources: [chunk1, chunk2],
        ),
      ),
    );

    expect(find.widgetWithText(ActionChip, 'Repeated content'), findsOneWidget);
  });

  testWidgets(
    'configures TextOverflow.ellipsis and collapses whitespace for '
    'chunk content',
    (tester) async {
      final longChunk = SearchResult(
        id: 'chunk-long',
        content:
            'Line 1 of content\n\nLine 2 with extra   spaces\nand long text ' *
            10,
        score: 0.9,
        metadata: {'documentTitle': 'Large.pdf'},
      );

      await tester.pumpWidget(
        buildSubject(
          ChatMessage(
            content: 'Answer',
            isUser: false,
            timestamp: DateTime(2024, 1, 2, 3, 4),
            sources: [longChunk],
          ),
        ),
      );

      final textFinder = find.descendant(
        of: find.byType(ActionChip),
        matching: find.byType(Text),
      );
      expect(textFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.overflow, TextOverflow.ellipsis);
      expect(textWidget.maxLines, 1);
      expect(textWidget.data, isNot(contains('\n')));
    },
  );
}
