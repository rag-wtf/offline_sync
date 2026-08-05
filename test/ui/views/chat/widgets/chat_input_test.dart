import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/l10n/l10n.dart';
import 'package:offline_sync/ui/views/chat/widgets/chat_input.dart';

void main() {
  Widget buildSubject({
    required void Function(String) onSend,
    VoidCallback? onAttach,
    VoidCallback? onFilter,
    bool isProcessing = false,
    bool hasActiveFilters = false,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatInput(
          onSend: onSend,
          onAttach: onAttach ?? () {},
          onFilter: onFilter ?? () {},
          isProcessing: isProcessing,
          hasActiveFilters: hasActiveFilters,
        ),
      ),
    );
  }

  testWidgets('trims text before sending', (tester) async {
    String? sentText;

    await tester.pumpWidget(buildSubject(onSend: (value) => sentText = value));

    await tester.enterText(find.byType(TextField), '  hello world  ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(sentText, 'hello world');
  });

  testWidgets('does not send whitespace-only text', (tester) async {
    var sendCount = 0;

    await tester.pumpWidget(buildSubject(onSend: (_) => sendCount++));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sendCount, 0);
  });

  testWidgets('does not submit from keyboard while processing', (tester) async {
    var sendCount = 0;

    await tester.pumpWidget(
      buildSubject(onSend: (_) => sendCount++, isProcessing: true),
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sendCount, 0);
  });

  testWidgets('invokes attach and filter actions', (tester) async {
    var attachCount = 0;
    var filterCount = 0;

    await tester.pumpWidget(
      buildSubject(
        onSend: (_) {},
        onAttach: () => attachCount++,
        onFilter: () => filterCount++,
        hasActiveFilters: true,
      ),
    );

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pump();

    expect(attachCount, 1);
    expect(filterCount, 1);
    expect(find.byType(Positioned), findsOneWidget);
  });

  testWidgets('send button is disabled while processing', (tester) async {
    var sendCount = 0;

    await tester.pumpWidget(
      buildSubject(onSend: (_) => sendCount++, isProcessing: true),
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(sendCount, 0);
  });
}
