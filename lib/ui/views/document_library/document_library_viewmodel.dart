import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class DocumentLibraryViewModel extends BaseViewModel {
  DocumentLibraryViewModel({
    DocumentManagementService? documentService,
    NavigationService? navigationService,
    DialogService? dialogService,
    RagSettingsService? settingsService,
  }) : _documentService =
           documentService ?? locator<DocumentManagementService>(),
       _navigationService = navigationService ?? locator<NavigationService>(),
       _dialogService = dialogService ?? locator<DialogService>(),
       _settingsService =
           settingsService ??
           (locator.isRegistered<RagSettingsService>()
               ? locator<RagSettingsService>()
               : RagSettingsService());

  final DocumentManagementService _documentService;
  final NavigationService _navigationService;
  final DialogService _dialogService;
  final RagSettingsService _settingsService;

  List<Document> _documents = [];
  List<Document> get documents => _documents;

  // Track active ingestion progress per document
  final Map<String, IngestionProgress> _activeIngestions = {};
  Map<String, IngestionProgress> get activeIngestions => _activeIngestions;
  StreamSubscription<IngestionProgress>? _progressSubscription;

  bool get isIngesting => _activeIngestions.isNotEmpty;

  bool needsReindex(Document document) =>
      document.status == IngestionStatus.complete &&
      document.embeddingModelId != null &&
      document.embeddingModelId != _settingsService.activeEmbeddingModelId;

  AppLocalizations? get _l10n {
    final context = StackedService.navigatorKey?.currentContext;
    if (context == null) return null;
    return AppLocalizations.of(context); // coverage:ignore-line
  }

  @visibleForTesting
  static Future<List<PlatformFile>> Function({
    required FileType type,
    required List<String> allowedExtensions,
  })
  pickFiles = FilePicker.pickFiles;

  Future<void> initialize() async {
    setBusy(true);
    try {
      await _refreshDocuments();
    } finally {
      setBusy(false);
    }

    // Listen to progress stream to update UI in real-time
    _progressSubscription = _documentService.ingestionProgressStream.listen((
      event,
    ) async {
      if (disposed) return;
      // Update active ingestion tracking
      if (event.stage == 'complete' || event.stage == 'error') {
        // Keep the final state briefly before removing
        _activeIngestions[event.documentId] = event;
        notifyListeners();

        // Wait a moment to show completion/error, then remove
        await Future<void>.delayed(const Duration(seconds: 2));
        if (disposed) return;
        _activeIngestions.remove(event.documentId);

        await _refreshDocuments();
        if (event.stage == 'error') {
          await _dialogService.showDialog(
            title: _l10n?.ingestionErrorTitle ?? 'Ingestion Error',
            description:
                _l10n?.failedToProcessDocument(event.documentTitle) ??
                'Failed to process ${event.documentTitle}.',
          );
        }
      } else {
        // Update progress for ongoing ingestion
        _activeIngestions[event.documentId] = event;
      }
      notifyListeners();
    });
  }

  Future<void> _refreshDocuments() async {
    _documents = await _documentService.getAllDocuments();
    notifyListeners();
  }

  Future<void> pickAndIngestFile() async {
    final files = await pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'epub', 'json'],
    );

    if (files.isNotEmpty) {
      for (final file in files) {
        try {
          await _documentService.addDocumentFromPlatformFile(file);
        } on Object catch (_) {
          await _dialogService.showDialog(
            title: _l10n?.errorTitle ?? 'Error',
            description:
                _l10n?.failedToProcessDocument(file.name) ??
                'Failed to add ${file.name}.',
          );
        }
      }

      await _refreshDocuments();
    }
  }

  Future<bool> deleteDocument(Document doc) async {
    final response = await _dialogService.showConfirmationDialog(
      title: _l10n?.deleteDocumentTitle ?? 'Delete Document?',
      description:
          _l10n?.deleteDocumentDescription(doc.title) ??
          'Are you sure you want to delete "${doc.title}"? '
              'This will remove all associated knowledge chunks.',
      confirmationTitle: _l10n?.deleteAction ?? 'Delete',
    );

    final confirmed = response?.confirmed ?? false;
    if (confirmed) {
      setBusy(true);
      try {
        await _documentService.deleteDocument(doc.id);
        await _refreshDocuments();
      } finally {
        setBusy(false);
      }
    }

    return confirmed;
  }

  Future<void> showDocumentDetails(Document doc) async {
    await _navigationService.navigateTo<dynamic>(
      Routes.documentDetailView,
      arguments: DocumentDetailViewArguments(document: doc),
    );
  }

  Future<bool> reindexDocument(Document document) async {
    setBusy(true);
    try {
      await _documentService.reindexDocument(document.id);
      await _refreshDocuments();
      return true;
    } on Object catch (_) {
      await _dialogService.showDialog(
        title: _l10n?.errorTitle ?? 'Error',
        description:
            _l10n?.failedToProcessDocument(document.title) ??
            'Failed to re-index ${document.title}.',
      );
      return false;
    } finally {
      setBusy(false);
    }
  }

  Future<void> renameDocument(Document document, String title) async {
    try {
      await _documentService.renameDocument(document.id, title);
      await _refreshDocuments();
    } on Object catch (_) {
      await _dialogService.showDialog(
        title: _l10n?.errorTitle ?? 'Error',
        description:
            _l10n?.renameDocumentError ?? 'Unable to rename this document.',
      );
    }
  }

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    super.dispose();
  }
}
