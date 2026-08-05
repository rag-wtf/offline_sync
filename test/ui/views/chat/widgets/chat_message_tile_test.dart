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

  testWidgets('renders source chips and sends source clicks to callback', (
    tester,
  ) async {
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
    expect(find.widgetWithText(ActionChip, 'Guide.pdf'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Guide.pdf'));
    await tester.pump();

    expect(selectedSource, same(source));
  });

  testWidgets('uses fallback source title and tolerates absent callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        ChatMessage(
          content: 'Answer',
          isUser: false,
          timestamp: DateTime(2024, 1, 2, 3, 4),
          sources: [
            SearchResult(
              id: 'source-2',
              content: 'Relevant context',
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
}
