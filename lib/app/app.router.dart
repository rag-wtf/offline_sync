// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// StackedNavigatorGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/foundation.dart' as _i8;
import 'package:flutter/material.dart' as _i7;
import 'package:flutter/material.dart';
import 'package:offline_sync/models/document.dart' as _i9;
import 'package:offline_sync/ui/views/chat/chat_view.dart' as _i3;
import 'package:offline_sync/ui/views/document_detail/document_detail_view.dart'
    as _i6;
import 'package:offline_sync/ui/views/document_library/document_library_view.dart'
    as _i5;
import 'package:offline_sync/ui/views/settings/settings_view.dart' as _i4;
import 'package:offline_sync/ui/views/startup/startup_view.dart' as _i2;
import 'package:stacked/stacked.dart' as _i1;
import 'package:stacked_services/stacked_services.dart' as _i10;

class Routes {
  static const startupView = '/';

  static const chatView = '/chat-view';

  static const settingsView = '/settings-view';

  static const documentLibraryView = '/document-library-view';

  static const documentDetailView = '/document-detail-view';

  static const all = <String>{
    startupView,
    chatView,
    settingsView,
    documentLibraryView,
    documentDetailView,
  };
}

class StackedRouter extends _i1.RouterBase {
  final _routes = <_i1.RouteDef>[
    _i1.RouteDef(Routes.startupView, page: _i2.StartupView),
    _i1.RouteDef(Routes.chatView, page: _i3.ChatView),
    _i1.RouteDef(Routes.settingsView, page: _i4.SettingsView),
    _i1.RouteDef(Routes.documentLibraryView, page: _i5.DocumentLibraryView),
    _i1.RouteDef(Routes.documentDetailView, page: _i6.DocumentDetailView),
  ];

  final _pagesMap = <Type, _i1.StackedRouteFactory>{
    _i2.StartupView: (data) {
      final args = data.getArgs<StartupViewArguments>(
        orElse: () => const StartupViewArguments(),
      );
      return _i7.MaterialPageRoute<dynamic>(
        builder: (context) => _i2.StartupView(key: args.key),
        settings: data,
      );
    },
    _i3.ChatView: (data) {
      final args = data.getArgs<ChatViewArguments>(
        orElse: () => const ChatViewArguments(),
      );
      return _i7.MaterialPageRoute<dynamic>(
        builder: (context) => _i3.ChatView(key: args.key),
        settings: data,
      );
    },
    _i4.SettingsView: (data) {
      final args = data.getArgs<SettingsViewArguments>(
        orElse: () => const SettingsViewArguments(),
      );
      return _i7.MaterialPageRoute<dynamic>(
        builder: (context) => _i4.SettingsView(key: args.key),
        settings: data,
      );
    },
    _i5.DocumentLibraryView: (data) {
      final args = data.getArgs<DocumentLibraryViewArguments>(
        orElse: () => const DocumentLibraryViewArguments(),
      );
      return _i7.MaterialPageRoute<dynamic>(
        builder: (context) => _i5.DocumentLibraryView(key: args.key),
        settings: data,
      );
    },
    _i6.DocumentDetailView: (data) {
      final args = data.getArgs<DocumentDetailViewArguments>(nullOk: false);
      return _i7.MaterialPageRoute<dynamic>(
        builder: (context) =>
            _i6.DocumentDetailView(document: args.document, key: args.key),
        settings: data,
      );
    },
  };

  @override
  List<_i1.RouteDef> get routes => _routes;

  @override
  Map<Type, _i1.StackedRouteFactory> get pagesMap => _pagesMap;
}

class StartupViewArguments {
  const StartupViewArguments({this.key});

  final _i8.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant StartupViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class ChatViewArguments {
  const ChatViewArguments({this.key});

  final _i8.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant ChatViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class SettingsViewArguments {
  const SettingsViewArguments({this.key});

  final _i8.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant SettingsViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DocumentLibraryViewArguments {
  const DocumentLibraryViewArguments({this.key});

  final _i8.Key? key;

  @override
  String toString() {
    return '{"key": "$key"}';
  }

  @override
  bool operator ==(covariant DocumentLibraryViewArguments other) {
    if (identical(this, other)) return true;
    return other.key == key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }
}

class DocumentDetailViewArguments {
  const DocumentDetailViewArguments({required this.document, this.key});

  final _i9.Document document;

  final _i8.Key? key;

  @override
  String toString() {
    return '{"document": "$document", "key": "$key"}';
  }

  @override
  bool operator ==(covariant DocumentDetailViewArguments other) {
    if (identical(this, other)) return true;
    return other.document == document && other.key == key;
  }

  @override
  int get hashCode {
    return document.hashCode ^ key.hashCode;
  }
}

extension NavigatorStateExtension on _i10.NavigationService {
  Future<dynamic> navigateToStartupView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.startupView,
      arguments: StartupViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToChatView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.chatView,
      arguments: ChatViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToSettingsView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.settingsView,
      arguments: SettingsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDocumentLibraryView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.documentLibraryView,
      arguments: DocumentLibraryViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> navigateToDocumentDetailView({
    required _i9.Document document,
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return navigateTo<dynamic>(
      Routes.documentDetailView,
      arguments: DocumentDetailViewArguments(document: document, key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithStartupView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.startupView,
      arguments: StartupViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithChatView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.chatView,
      arguments: ChatViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithSettingsView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.settingsView,
      arguments: SettingsViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDocumentLibraryView({
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.documentLibraryView,
      arguments: DocumentLibraryViewArguments(key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }

  Future<dynamic> replaceWithDocumentDetailView({
    required _i9.Document document,
    _i8.Key? key,
    int? routerId,
    bool preventDuplicates = true,
    Map<String, String>? parameters,
    Widget Function(BuildContext, Animation<double>, Animation<double>, Widget)?
    transition,
  }) async {
    return replaceWith<dynamic>(
      Routes.documentDetailView,
      arguments: DocumentDetailViewArguments(document: document, key: key),
      id: routerId,
      preventDuplicates: preventDuplicates,
      parameters: parameters,
      transition: transition,
    );
  }
}
