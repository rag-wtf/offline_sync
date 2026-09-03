import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';

void main() {
  Widget buildSubject({
    String? repoPage,
    String? modelName,
    Future<void> Function(String token)? onSaveToken,
    Future<bool> Function(Uri uri)? onLaunchUrl,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                unawaited(
                  showDialog<bool>(
                    context: context,
                    builder: (_) => TokenInputDialog(
                      repoPage: repoPage,
                      modelName: modelName,
                      onSaveToken: onSaveToken,
                      onLaunchUrl: onLaunchUrl,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    final openButton = find.text('open');
    if (openButton.evaluate().isNotEmpty) {
      await tester.tap(openButton);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows validation for empty token', (tester) async {
    await openDialog(tester, buildSubject());

    await tester.tap(find.text('Save & Continue'));
    await tester.pump();

    expect(find.text('Token cannot be empty'), findsOneWidget);
  });

  testWidgets('shows validation for invalid token prefix', (tester) async {
    await openDialog(tester, buildSubject());

    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.tap(find.text('Save & Continue'));
    await tester.pump();

    expect(find.textContaining('Invalid token format'), findsOneWidget);
  });

  testWidgets('saves valid token and closes'
      ' dialog with success', (tester) async {
    String? savedToken;

    await openDialog(
      tester,
      buildSubject(onSaveToken: (token) async => savedToken = token),
    );

    await tester.enterText(find.byType(TextField), 'hf_secret');
    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    expect(savedToken, 'hf_secret');
    expect(find.byType(TokenInputDialog), findsNothing);
  });

  testWidgets('shows error message when onSaveToken throws exception', (
    tester,
  ) async {
    await openDialog(
      tester,
      buildSubject(
        onSaveToken: (token) async => throw Exception('Storage error'),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hf_secret');
    await tester.tap(find.text('Save & Continue'));
    await tester.pump();

    expect(
      find.text('Failed to save token: Exception: Storage error'),
      findsOneWidget,
    );
  });

  testWidgets(
    'displays note about fine-grained gated repository token permission',
    (tester) async {
      await openDialog(tester, buildSubject());
      expect(
        find.textContaining('public gated repos'),
        findsOneWidget,
      );
    },
  );

  testWidgets('displays repo link when repoPage is provided', (tester) async {
    await openDialog(
      tester,
      const MaterialApp(
        home: Scaffold(
          body: TokenInputDialog(
            repoPage: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
            modelName: 'Gemma 3 1B IT',
          ),
        ),
      ),
    );
    expect(
      find.textContaining('litert-community/Gemma3-1B-IT'),
      findsOneWidget,
    );
  });
}
