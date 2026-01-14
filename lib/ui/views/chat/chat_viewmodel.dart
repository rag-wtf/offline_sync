import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class ChatMessage {
  ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.sources,
    this.metrics,
  });
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<SearchResult>? sources;
  final RAGMetrics? metrics;
}

class ChatViewModel extends BaseViewModel {
  final RagService _ragService = locator<RagService>();
  final SnackbarService _snackbarService = locator<SnackbarService>();
  final NavigationService _navigationService = locator<NavigationService>();

  final List<ChatMessage> messages = [];
  final ScrollController scrollController = ScrollController();
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  bool _shouldScroll = false;
  bool get shouldScroll => _shouldScroll;

  void onScrolled() {
    _shouldScroll = false;
  }

  Future<void> initialize() async {
    setBusy(true);
    try {
      await _ragService.initialize();
    } on Exception catch (e) {
      _snackbarService.showSnackbar(message: 'Initialization error: $e');
    } finally {
      setBusy(false);
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isProcessing) return;

    final userMsg = ChatMessage(
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);
    _shouldScroll = true;
    notifyListeners();

    _isProcessing = true;
    notifyListeners();

    try {
      final result = await _ragService.askWithRAG(text, includeMetrics: true);

      messages.add(
        ChatMessage(
          content: result.response,
          isUser: false,
          timestamp: DateTime.now(),
          sources: result.sources,
          metrics: result.metrics,
        ),
      );
      _shouldScroll = true;
    } on AuthenticationRequiredException {
      // Show token input dialog
      await _showTokenDialog();
      _snackbarService.showSnackbar(
        message: 'Please provide authentication and try again',
      );
    } on Exception catch (e) {
      _snackbarService.showSnackbar(message: 'Error: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> pickAndIngestFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'txt',
        'md',
        'pdf',
      ], // PDF requires extra parsing, focusing on text for now
    );

    if (result == null || result.files.isEmpty) return;

    setBusy(true);
    var ingestedCount = 0;

    try {
      for (final file in result.files) {
        if (file.path == null) continue;

        final content = await _readFileContent(file.path!);
        await _ragService.ingestDocument(file.name, content);
        ingestedCount++;
      }

      _snackbarService.showSnackbar(
        message: 'Successfully ingested $ingestedCount file(s)',
      );
    } on AuthenticationRequiredException {
      // Show token input dialog
      await _showTokenDialog();
      _snackbarService.showSnackbar(
        message: 'Please provide authentication and try again',
      );
    } on Exception catch (e) {
      _snackbarService.showSnackbar(message: 'Ingestion error: $e');
    } finally {
      setBusy(false);
    }
  }

  Future<String> _readFileContent(String path) async {
    // Basic text reader. For PDF, we'd need sync_fusion or similar.
    // Assuming text/markdown for Phase 1.
    return Stream.fromIterable([path])
        .asyncMap(
          (p) async => (p.endsWith('.pdf'))
              ? 'PDF parsing not implemented'
              : await _readText(p),
        )
        .first;
  }

  Future<String> _readText(String path) async {
    final file = File(path);
    return file.readAsString();
  }

  Future<void> _showTokenDialog() async {
    await _navigationService.navigateWithTransition<bool?>(
      const TokenInputDialog(),
      transitionStyle: Transition.fade,
    );
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
