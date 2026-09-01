import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/exceptions.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

/// Represents a single message in the chat history
class ChatMessage {
  ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.sources,
    this.metrics,
  });

  /// The text content of the message
  final String content;

  /// Whether the message was sent by the user
  final bool isUser;

  /// When the message was sent
  final DateTime timestamp;

  /// Source documents used for RAG generation (if AI message)
  final List<SearchResult>? sources;

  /// Performance metrics for the RAG generation (if AI message)
  final RAGMetrics? metrics;
}

/// ViewModel for the chat view, handling message sending and document ingestion
class ChatViewModel extends BaseViewModel {
  final RagService _ragService = locator<RagService>();
  final SnackbarService _snackbarService = locator<SnackbarService>();
  final NavigationService _navigationService = locator<NavigationService>();
  final ChatRepository _chatRepository = locator<ChatRepository>();
  final DialogService _dialogService = locator<DialogService>();
  final DocumentManagementService _documentService =
      locator<DocumentManagementService>();
  final RagSettingsService _ragSettings = locator<RagSettingsService>();

  /// List of messages in the current conversation
  final List<ChatMessage> messages = [];

  /// Controller for scrolling the chat list
  final ScrollController scrollController = ScrollController();

  StreamSubscription<IngestionProgress>? _progressSubscription;

  IngestionProgress? _currentIngestionProgress;

  /// Current file ingestion progress event
  IngestionProgress? get currentIngestionProgress => _currentIngestionProgress;

  /// Whether a file is currently being ingested
  bool get isIngesting =>
      _currentIngestionProgress != null &&
      _currentIngestionProgress!.stage != 'complete' &&
      _currentIngestionProgress!.stage != 'error';

  List<Document> _availableDocuments = [];

  /// Documents available for filtering the search
  List<Document> get availableDocuments => _availableDocuments;

  final Set<String> _selectedDocumentIds = {};

  /// IDs of documents selected for search filtering
  Set<String> get selectedDocumentIds => _selectedDocumentIds;

  bool _isProcessing = false;

  /// Whether a RAG query is currently in progress
  bool get isProcessing => _isProcessing;

  bool _shouldScroll = false;

  /// Whether the chat view should scroll to the bottom
  bool get shouldScroll => _shouldScroll;

  @visibleForTesting
  static Future<FilePickerResult?> Function({
    required FileType type,
    required List<String> allowedExtensions,
  })
  pickFiles = FilePicker.pickFiles;

  /// Called when the user manualy scrolls the list
  void onScrolled() {
    _shouldScroll = false;
  }

  void toggleDocumentSelection(String docId) {
    if (_selectedDocumentIds.contains(docId)) {
      _selectedDocumentIds.remove(docId);
    } else {
      _selectedDocumentIds.add(docId);
    }
    notifyListeners();
  }

  /// Initializes the ViewModel, loading history and available documents
  Future<void> initialize() async {
    setBusy(true);
    try {
      await _ragService.initialize();
      // Load previous chat history
      final history = await _chatRepository.loadMessages();
      messages.addAll(history);
      if (messages.isNotEmpty) {
        _shouldScroll = true;
      }

      await _refreshDocuments();

      // Listen to ingestion events to update UI and available documents
      _progressSubscription = _documentService.ingestionProgressStream.listen((
        event,
      ) async {
        if (disposed) return;
        _currentIngestionProgress = event;
        notifyListeners();

        if (event.stage == 'complete') {
          await _refreshDocuments();
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          if (disposed) return;
          if (_currentIngestionProgress?.documentId == event.documentId) {
            _currentIngestionProgress = null;
            notifyListeners();
          }
        } else if (event.stage == 'error') {
          await Future<void>.delayed(const Duration(seconds: 2));
          if (disposed) return;
          if (_currentIngestionProgress?.documentId == event.documentId) {
            _currentIngestionProgress = null;
            notifyListeners();
          }
        }
      });
    } on Object catch (e) {
      _snackbarService.showSnackbar(
        message: 'Initialization error: $e',
        duration: const Duration(seconds: 3),
      );
    } finally {
      setBusy(false);
    }
  }

  Future<void> _refreshDocuments() async {
    final allDocuments = await _documentService.getAllDocuments();
    // Filter to only show successfully indexed documents
    _availableDocuments = allDocuments
        .where((doc) => doc.status == IngestionStatus.complete)
        .toList();
    notifyListeners();
  }

  /// Sends a user message and triggers a RAG query
  /// Updates the messages list in real-time as tokens are streamed back
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isProcessing) return;

    _isProcessing = true;
    notifyListeners();

    final userMsg = ChatMessage(
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);
    await _chatRepository.saveMessage(userMsg); // Persist user message
    _shouldScroll = true;
    notifyListeners();

    // Add placeholder AI message that will be updated with streaming content
    final aiMsgIndex = messages.length;
    final aiMsg = ChatMessage(
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
    );
    messages.add(aiMsg);
    _shouldScroll = true;
    notifyListeners();

    try {
      // Build history (excluding placeholder AI message & current user query)
      final maxHistoryMessages = _ragSettings.maxHistoryMessages;
      final history = messages.reversed
          .skip(2) // Skip placeholder AI message and current user query
          .take(maxHistoryMessages)
          .toList()
          .reversed
          .map((m) => '${m.isUser ? "User" : "AI"}: ${m.content}')
          .toList();

      List<SearchResult>? sources;
      RAGMetrics? metrics;

      // Stream tokens and update the message incrementally
      await for (final event in _ragService.askWithRAGStream(
        text,
        includeMetrics: true,
        conversationHistory: history.isNotEmpty ? history : null,
        documentIds: _selectedDocumentIds.isNotEmpty
            ? _selectedDocumentIds.toList()
            : null,
      )) {
        if (disposed) break;
        if (event is RAGMetadataEvent) {
          // Store sources and metrics for later
          sources = event.sources;
          metrics = event.metrics;
        } else if (event is RAGTokenEvent) {
          // Update the message content with the new token
          messages[aiMsgIndex] = ChatMessage(
            content: messages[aiMsgIndex].content + event.token,
            isUser: false,
            timestamp: messages[aiMsgIndex].timestamp,
            sources: sources,
            metrics: metrics,
          );
          _shouldScroll = true;
          notifyListeners(); // Trigger UI update for each token
        } else if (event is RAGCompleteEvent) {
          // Clean trailing disclaimer if meaningful response exists
          final rawContent = messages[aiMsgIndex].content;
          final cleanedContent = RagService.cleanResponse(rawContent);
          if (cleanedContent != rawContent) {
            messages[aiMsgIndex] = ChatMessage(
              content: cleanedContent,
              isUser: false,
              timestamp: messages[aiMsgIndex].timestamp,
              sources: sources,
              metrics: metrics,
            );
            notifyListeners();
          }
          // Stream completed, persist the final message
          await _chatRepository.saveMessage(messages[aiMsgIndex]);
        }
      }
    } on AuthenticationRequiredException {
      // Remove the placeholder message on error
      messages.removeAt(aiMsgIndex);
      // Show token input dialog
      await _showTokenDialog();
      _snackbarService.showSnackbar(
        message: 'Please provide authentication and try again',
        duration: const Duration(seconds: 3),
      );
    } on Object catch (e) {
      // Remove the placeholder message on error
      if (messages.length > aiMsgIndex) {
        messages.removeAt(aiMsgIndex);
      }
      _snackbarService.showSnackbar(
        message: 'Error: $e',
        duration: const Duration(seconds: 3),
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Shows a detailed view of a source document used for context
  Future<void> showSourceDetail(SearchResult source) async {
    final title = source.documentTitle ??
        (source.metadata['documentTitle'] as String?) ??
        (source.metadata['title'] as String?) ??
        'Source Detail';

    final targetDocId = source.metadata['documentId'] as String?;

    // Find all chunks related to this document across messages
    final relatedChunks = <String>[];
    for (final msg in messages) {
      if (msg.sources != null) {
        for (final s in msg.sources!) {
          final sTitle = s.documentTitle ??
              (s.metadata['documentTitle'] as String?) ??
              (s.metadata['title'] as String?);
          final sDocId = s.metadata['documentId'] as String?;
          if ((targetDocId != null && sDocId == targetDocId) ||
              (sTitle != null && sTitle == title)) {
            if (!relatedChunks.contains(s.content)) {
              relatedChunks.add(s.content);
            }
          }
        }
      }
    }

    final content = relatedChunks.isNotEmpty
        ? relatedChunks.join('\n\n---\n\n')
        : source.content;

    await _dialogService.showDialog(
      title: title,
      description: content,
    );
  }

  /// Opens file picker and starts ingestion for one or more files
  Future<void> pickAndIngestFiles() async {
    final result = await pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'epub', 'json'],
    );

    if (result == null || result.files.isEmpty) return;

    try {
      // coverage:ignore-start
      if (kIsWeb) {
        for (final file in result.files) {
          await _documentService.addDocumentFromPlatformFile(file);
        }
        await _refreshDocuments();
        _snackbarService.showSnackbar(
          message: 'Ingested ${result.files.length} document(s)',
          duration: const Duration(seconds: 3),
        );
      } else {
        // coverage:ignore-end
        final paths = result.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList();

        if (paths.isEmpty) return;

        final ingestionResult = await _documentService.addMultipleDocuments(
          paths,
        );

        if (ingestionResult.hasErrors) {
          final failedCount = ingestionResult.failed.length;
          final successCount = ingestionResult.succeeded.length;

          if (successCount == 0) {
            _snackbarService.showSnackbar(
              message: 'Failed to ingest $failedCount file(s)',
              duration: const Duration(seconds: 3),
            );
          } else {
            _snackbarService.showSnackbar(
              message:
                  'Ingested $successCount file(s). '
                  'Failed to ingest $failedCount file(s).',
              duration: const Duration(seconds: 3),
            );
          }
        } else {
          _snackbarService.showSnackbar(
            message:
                'Successfully ingested '
                '${ingestionResult.succeeded.length} file(s)',
            duration: const Duration(seconds: 3),
          );
        }
      }
    } on Object catch (e) {
      _snackbarService.showSnackbar(
        message: 'Ingestion error: $e',
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _showTokenDialog() async {
    await _navigationService.navigateWithTransition<bool?>(
      const TokenInputDialog(),
      transitionStyle: Transition.fade,
    );
  }

  Future<void> navigateToSettings() async {
    await _navigationService.navigateToSettingsView();
  }

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    scrollController.dispose();
    super.dispose();
  }
}
