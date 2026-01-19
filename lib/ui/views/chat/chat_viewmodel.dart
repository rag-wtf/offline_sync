import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/document_management_service.dart';
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
  final ChatRepository _chatRepository = locator<ChatRepository>();
  final DialogService _dialogService = locator<DialogService>();
  final DocumentManagementService _documentService =
      locator<DocumentManagementService>();

  final List<ChatMessage> messages = [];
  final ScrollController scrollController = ScrollController();

  List<Document> _availableDocuments = [];
  List<Document> get availableDocuments => _availableDocuments;

  final Set<String> _selectedDocumentIds = {};
  Set<String> get selectedDocumentIds => _selectedDocumentIds;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  bool _shouldScroll = false;
  bool get shouldScroll => _shouldScroll;

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

      // Listen to ingestion events to update available documents
      _documentService.ingestionProgressStream.listen((event) async {
        if (event.stage == 'complete') {
          await _refreshDocuments();
        }
      });
    } on Exception catch (e) {
      _snackbarService.showSnackbar(message: 'Initialization error: $e');
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

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isProcessing) return;

    final userMsg = ChatMessage(
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    messages.add(userMsg);
    await _chatRepository.saveMessage(userMsg); // Persist user message
    _shouldScroll = true;
    notifyListeners();

    _isProcessing = true;
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
      // Build conversation history from last 10 messages (excluding current)
      final history = messages
          .take(messages.length > 10 ? 10 : messages.length)
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
      );
    } on Exception catch (e) {
      // Remove the placeholder message on error
      messages.removeAt(aiMsgIndex);
      _snackbarService.showSnackbar(message: 'Error: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> showSourceDetail(SearchResult source) async {
    // If we have documentId in metadata, we can navigate to detail view
    final docId = source.metadata['documentId'] as String?;
    if (docId != null) {
      // For now, show a dialog with the content as we can't easily fetch
      // the Document object without adding a method to
      // DocumentManagementService.
      // Phase 4 requirement: Source detail bottom sheet
      // (impl as dialog/bottom sheet)

      await _dialogService.showDialog(
        title: (source.metadata['documentTitle'] as String?) ?? 'Source Detail',
        description: source.content,
      );
    }
  }

  Future<void> pickAndIngestFiles() async {
    // Use DocumentLibraryViewModel's logic or delegate?
    // Duplicate logic is fine for now but ideally we use the service.

    // Actually, why not just navigate to DocumentLibraryView?
    // User might want to ingest *while* in chat.

    final docService = locator<DocumentManagementService>();
    // ... use docService.addDocument ...

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'epub', 'json'],
    );

    if (result == null || result.files.isEmpty) return;

    setBusy(true);
    var ingestedCount = 0;

    try {
      for (final file in result.files) {
        if (file.path == null) continue;
        await docService.addDocument(file.path!);
        ingestedCount++;
      }

      _snackbarService.showSnackbar(
        message: 'Successfully ingested $ingestedCount file(s)',
      );
    } on Exception catch (e) {
      _snackbarService.showSnackbar(message: 'Ingestion error: $e');
    } finally {
      setBusy(false);
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
    scrollController.dispose();
    super.dispose();
  }
}
