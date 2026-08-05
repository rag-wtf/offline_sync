import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/ui/views/chat/chat_view.dart';
import 'package:offline_sync/ui/views/document_detail/document_detail_view.dart';
import 'package:offline_sync/ui/views/document_library/document_library_view.dart';
import 'package:offline_sync/ui/views/settings/settings_view.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('app.router', () {
    late MockNavigationService navigationService;
    late Document document;

    setUp(() {
      navigationService = MockNavigationService();
      document = Document(
        id: 'doc-1',
        title: 'Doc',
        filePath: '/tmp/doc.md',
        format: DocumentFormat.markdown,
        chunkCount: 2,
        totalCharacters: 100,
        contentHash: 'hash',
        ingestedAt: DateTime(2024),
      );

      when(
        () => navigationService.navigateTo<dynamic>(
          any<String>(),
          arguments: any<dynamic>(named: 'arguments'),
          id: any<int?>(named: 'id'),
          preventDuplicates: any<bool>(named: 'preventDuplicates'),
          parameters: any<Map<String, String>?>(named: 'parameters'),
          transition: any<RouteTransitionsBuilder?>(named: 'transition'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => navigationService.replaceWith<dynamic>(
          any<String>(),
          arguments: any<dynamic>(named: 'arguments'),
          id: any<int?>(named: 'id'),
          preventDuplicates: any<bool>(named: 'preventDuplicates'),
          parameters: any<Map<String, String>?>(named: 'parameters'),
          transition: any<RouteTransitionsBuilder?>(named: 'transition'),
        ),
      ).thenAnswer((_) async {});
    });

    test('defines all expected routes and page builders', () {
      final router = StackedRouter();

      expect(Routes.all, {
        Routes.startupView,
        Routes.chatView,
        Routes.settingsView,
        Routes.documentLibraryView,
        Routes.documentDetailView,
      });
      expect(router.routes, hasLength(5));
      expect(router.pagesMap.keys, hasLength(5));
    });

    test('argument value types implement equality, hashCode and toString', () {
      const startupA = StartupViewArguments(key: ValueKey('startup'));
      const startupB = StartupViewArguments(key: ValueKey('startup'));
      const startupC = StartupViewArguments(key: ValueKey('other-startup'));
      const chatArgs = ChatViewArguments(key: ValueKey('chat'));
      const sameChatArgs = ChatViewArguments(key: ValueKey('chat'));
      const otherChatArgs = ChatViewArguments(key: ValueKey('other-chat'));
      const settingsArgs = SettingsViewArguments(key: ValueKey('settings'));
      const sameSettingsArgs = SettingsViewArguments(key: ValueKey('settings'));
      const otherSettingsArgs = SettingsViewArguments(
        key: ValueKey('other-settings'),
      );
      const libraryArgs = DocumentLibraryViewArguments(
        key: ValueKey('library'),
      );
      const sameLibraryArgs = DocumentLibraryViewArguments(
        key: ValueKey('library'),
      );
      const otherLibraryArgs = DocumentLibraryViewArguments(
        key: ValueKey('other-library'),
      );
      final detailA = DocumentDetailViewArguments(document: document);
      final detailB = DocumentDetailViewArguments(document: document);

      expect(startupA, startupB);
      expect(startupA == startupC, isFalse);
      expect(startupA.hashCode, startupB.hashCode);
      expect(startupA.toString(), contains('startup'));
      expect(chatArgs, sameChatArgs);
      expect(chatArgs.toString(), contains('key'));
      expect(chatArgs == otherChatArgs, isFalse);
      expect(chatArgs.hashCode, chatArgs.key.hashCode);
      expect(settingsArgs, sameSettingsArgs);
      expect(settingsArgs.toString(), contains('key'));
      expect(settingsArgs == otherSettingsArgs, isFalse);
      expect(settingsArgs.hashCode, settingsArgs.key.hashCode);
      expect(libraryArgs, sameLibraryArgs);
      expect(libraryArgs.toString(), contains('key'));
      expect(libraryArgs == otherLibraryArgs, isFalse);
      expect(libraryArgs.hashCode, libraryArgs.key.hashCode);
      expect(detailA, detailB);
      expect(detailA.hashCode, detailB.hashCode);
      expect(detailA.toString(), contains('document'));
    });

    test('navigation extension forwards navigate and replace calls', () async {
      const startupKey = ValueKey('startup-route');
      const detailKey = ValueKey('detail-route');

      await navigationService.navigateToStartupView(key: startupKey);
      await navigationService.navigateToChatView();
      await navigationService.navigateToSettingsView();
      await navigationService.navigateToDocumentLibraryView();
      await navigationService.navigateToDocumentDetailView(
        document: document,
        key: detailKey,
      );
      await navigationService.replaceWithStartupView();
      await navigationService.replaceWithChatView();
      await navigationService.replaceWithSettingsView();
      await navigationService.replaceWithDocumentLibraryView();
      await navigationService.replaceWithDocumentDetailView(document: document);

      final startupArguments =
          verify(
                () => navigationService.navigateTo<dynamic>(
                  Routes.startupView,
                  arguments: captureAny<dynamic>(named: 'arguments'),
                  id: any<int?>(named: 'id'),
                  parameters: any<Map<String, String>?>(named: 'parameters'),
                  transition: any<RouteTransitionsBuilder?>(
                    named: 'transition',
                  ),
                ),
              ).captured.single
              as StartupViewArguments;
      expect(startupArguments.key, startupKey);

      final detailArguments =
          verify(
                () => navigationService.navigateTo<dynamic>(
                  Routes.documentDetailView,
                  arguments: captureAny<dynamic>(named: 'arguments'),
                  id: any<int?>(named: 'id'),
                  parameters: any<Map<String, String>?>(named: 'parameters'),
                  transition: any<RouteTransitionsBuilder?>(
                    named: 'transition',
                  ),
                ),
              ).captured.single
              as DocumentDetailViewArguments;
      expect(detailArguments.document, document);
      expect(detailArguments.key, detailKey);

      verify(
        () => navigationService.replaceWith<dynamic>(
          Routes.documentDetailView,
          arguments: any<dynamic>(named: 'arguments'),
          id: any<int?>(named: 'id'),
          parameters: any<Map<String, String>?>(named: 'parameters'),
          transition: any<RouteTransitionsBuilder?>(named: 'transition'),
        ),
      ).called(1);
    });

    testWidgets('route generation builds every page with its arguments', (
      tester,
    ) async {
      final router = StackedRouter();
      final routeArguments = <String, Object?>{
        Routes.startupView: const StartupViewArguments(),
        Routes.chatView: const ChatViewArguments(),
        Routes.settingsView: const SettingsViewArguments(),
        Routes.documentLibraryView: const DocumentLibraryViewArguments(),
        Routes.documentDetailView: DocumentDetailViewArguments(
          document: document,
        ),
      };
      final builtWidgets = <Widget>[];

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            for (final entry in routeArguments.entries) {
              final route = router.onGenerateRoute(
                RouteSettings(name: entry.key, arguments: entry.value),
              );
              expect(route, isA<MaterialPageRoute<dynamic>>());
              builtWidgets.add(
                (route! as MaterialPageRoute<dynamic>).builder(context),
              );
            }
            return const SizedBox();
          },
        ),
      );

      expect(builtWidgets, hasLength(routeArguments.length));
      expect(builtWidgets[0], isA<StartupView>());
      expect(builtWidgets[1], isA<ChatView>());
      expect(builtWidgets[2], isA<SettingsView>());
      expect(builtWidgets[3], isA<DocumentLibraryView>());
      expect(builtWidgets[4], isA<DocumentDetailView>());
    });

    testWidgets('route generation uses default arguments when none supplied', (
      tester,
    ) async {
      final router = StackedRouter();
      final routeNames = [
        Routes.startupView,
        Routes.chatView,
        Routes.settingsView,
        Routes.documentLibraryView,
      ];
      final builtWidgets = <Widget>[];

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            for (final routeName in routeNames) {
              final route = router.onGenerateRoute(
                RouteSettings(name: routeName),
              );
              expect(route, isA<MaterialPageRoute<dynamic>>());
              builtWidgets.add(
                (route! as MaterialPageRoute<dynamic>).builder(context),
              );
            }
            return const SizedBox();
          },
        ),
      );

      expect(builtWidgets[0], isA<StartupView>());
      expect(builtWidgets[1], isA<ChatView>());
      expect(builtWidgets[2], isA<SettingsView>());
      expect(builtWidgets[3], isA<DocumentLibraryView>());
    });

    test('required document detail arguments are rejected', () {
      expect(
        () => StackedRouter().onGenerateRoute(
          const RouteSettings(name: Routes.documentDetailView),
        ),
        throwsFlutterError,
      );
    });
  });
}
