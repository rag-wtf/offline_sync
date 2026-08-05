import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';

void main() {
  Widget buildSubject({
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
    await tester.tap(find.text('open'));
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

  testWidgets('shows error message when onSaveToken throws exception', (tester) async {
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
}
