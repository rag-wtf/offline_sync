import 'dart:async';

import 'package:flutter/services.dart';
// Constructor seams intentionally retain descriptive public parameter names.
// ignore_for_file: prefer_initializing_formals
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/ui/setup_dialog_ui.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class SettingsViewModel extends BaseViewModel {
  SettingsViewModel({
    ModelManagementService? modelService,
    RagSettingsService? ragSettings,
    NavigationService? navigationService,
    DeviceCapabilityService? deviceService,
    DialogService? dialogService,
    DocumentManagementService? documentService,
    Future<void> Function(String token)? saveTokenAction,
    Future<void> Function()? clearTokenAction,
    Future<void> Function()? clearChatHistoryAction,
    Future<List<String>> Function()? getCrashLogsAction,
    Future<void> Function()? clearCrashLogsAction,
  }) : _modelService = modelService ?? locator<ModelManagementService>(),
       _ragSettings = ragSettings ?? locator<RagSettingsService>(),
       _navigationService = navigationService ?? locator<NavigationService>(),
       _deviceService = deviceService ?? locator<DeviceCapabilityService>(),
       _dialogService =
           dialogService ??
           (locator.isRegistered<DialogService>()
               ? locator<DialogService>()
               : null),
       _documentService =
           documentService ??
           (locator.isRegistered<DocumentManagementService>()
               ? locator<DocumentManagementService>()
               : null),
       _saveTokenAction = saveTokenAction,
       _clearTokenAction = clearTokenAction,
       _clearChatHistoryAction = clearChatHistoryAction,
       _getCrashLogsAction = getCrashLogsAction,
       _clearCrashLogsAction = clearCrashLogsAction;

  final ModelManagementService _modelService;
  final RagSettingsService _ragSettings;
  final NavigationService _navigationService;
  final DeviceCapabilityService _deviceService;
  final DialogService? _dialogService;
  final DocumentManagementService? _documentService;
  final Future<void> Function(String token)? _saveTokenAction;
  final Future<void> Function()? _clearTokenAction;
  final Future<void> Function()? _clearChatHistoryAction;
  final Future<List<String>> Function()? _getCrashLogsAction;
  final Future<void> Function()? _clearCrashLogsAction;

  DeviceCapabilities? _capabilities;
  double? _pendingChunkOverlap;
  double? _pendingSemanticWeight;
  double? _pendingRerankTopK;
  double? _pendingMaxDocumentSize;
  double? _pendingSearchTopK;
  double? _pendingMaxHistoryMessages;
  double? _pendingMaxTokens;
  int _chunkOverlapDragToken = 0;
  int _semanticWeightDragToken = 0;
  int _rerankTopKDragToken = 0;
  int _maxDocumentSizeDragToken = 0;
  int _searchTopKDragToken = 0;
  int _maxHistoryMessagesDragToken = 0;
  int _maxTokensDragToken = 0;
  bool _hasModelStatusError = false;
  String? _actionError;
  List<String> _crashLogs = [];
  bool _isLoadingCrashLogs = false;
  bool? _hasToken;

  DeviceCapabilities? get capabilities => _capabilities;
  bool get hasModelStatusError => _hasModelStatusError;
  String? get actionError => _actionError;
  String? get settingsError => _actionError;
  List<String> get crashLogs => List.unmodifiable(_crashLogs);
  bool get isLoadingCrashLogs => _isLoadingCrashLogs;
  bool? get hasToken => _hasToken;

  AppLocalizations? get _l10n {
    try {
      final context = StackedService.navigatorKey?.currentContext;
      return context == null ? null : AppLocalizations.of(context);
    } on Object {
      return null;
    }
  }

  List<ModelInfo> get models => _modelService.models;

  // Model selection getters
  ModelInfo? get activeInferenceModel => _modelService.activeInferenceModel;
  ModelInfo? get activeEmbeddingModel => _modelService.activeEmbeddingModel;
  List<ModelInfo> get downloadedInferenceModels =>
      _modelService.downloadedInferenceModels;
  List<ModelInfo> get downloadedEmbeddingModels =>
      _modelService.downloadedEmbeddingModels;

  // RAG Settings getters
  bool get queryExpansionEnabled => _ragSettings.queryExpansionEnabled;
  bool get rerankingEnabled => _ragSettings.rerankingEnabled;
  bool get contextualRetrievalEnabled =>
      _ragSettings.contextualRetrievalEnabled;
  double get chunkOverlapDisplay =>
      _pendingChunkOverlap ?? (_ragSettings.chunkOverlapPercent * 100);
  double get semanticWeightDisplay =>
      _pendingSemanticWeight ?? _ragSettings.semanticWeight;
  double get rerankTopKDisplay =>
      _pendingRerankTopK ?? _ragSettings.rerankTopK.toDouble();
  double get searchTopKDisplay =>
      _pendingSearchTopK ?? _ragSettings.searchTopK.toDouble();
  double get maxHistoryMessagesDisplay =>
      _pendingMaxHistoryMessages ?? _ragSettings.maxHistoryMessages.toDouble();
  double get maxTokensDisplay => _pendingMaxTokens ?? maxTokens.toDouble();
  double get maxTokensLimit =>
      _ragSettings.activeInferenceContextLimit.toDouble();
  int get maxDocumentSizeMB => _ragSettings.maxDocumentSizeMB;
  double get maxDocumentSizeDisplay =>
      _pendingMaxDocumentSize ?? maxDocumentSizeMB.toDouble();

  // Get user-configured maxTokens or model default
  int get maxTokens {
    final userValue = _ragSettings.maxTokens;
    if (userValue != null) return userValue;

    // Return active model default
    return ModelConfig.activeInferenceModelOrDefault(
          _ragSettings.activeInferenceModelId,
        ).contextLimit ??
        ModelConfig.activeInferenceModelOrDefault(
          _ragSettings.activeInferenceModelId,
        ).maxTokens;
  }

  // Get the model's default maxTokens for display
  int get modelDefaultMaxTokens {
    return ModelConfig.activeInferenceModelOrDefault(
          _ragSettings.activeInferenceModelId,
        ).contextLimit ??
        ModelConfig.activeInferenceModelOrDefault(
          _ragSettings.activeInferenceModelId,
        ).maxTokens;
  }

  // Whether user has overridden the default
  bool get isMaxTokensCustom => _ragSettings.maxTokens != null;
  bool get isMaxTokensCustomDisplay {
    final pendingValue = _pendingMaxTokens;
    if (pendingValue != null) {
      return pendingValue.round() != modelDefaultMaxTokens;
    }

    return isMaxTokensCustom;
  }

  StreamSubscription<List<ModelInfo>>? _modelStatusSubscription;

  void setup() {
    _modelStatusSubscription = _modelService.modelStatusStream.listen(
      (_) {
        if (disposed) return;
        _hasModelStatusError = false;
        notifyListeners();
      },
      onError: (Object _, StackTrace _) {
        if (disposed) return;
        _hasModelStatusError = true;
        notifyListeners();
      },
    );
    unawaited(_initializeModels());
    unawaited(_loadTokenState());
    unawaited(loadCrashLogs());
    // Load device capabilities
    unawaited(_loadDeviceCapabilities());
  }

  Future<void> _loadDeviceCapabilities() async {
    try {
      _capabilities = await _deviceService.getCapabilities();
      if (disposed) return;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.settingsSaveError ??
          'Unable to load device information. Please try again.';
    }
    if (!disposed) notifyListeners();
  }

  Future<void> _loadTokenState() async {
    try {
      _hasToken = await AuthTokenService.hasToken();
      if (disposed) return;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.tokenStatusError ??
          'Unable to read token status. Please try again.';
    }
    if (!disposed) notifyListeners();
  }

  Future<void> _initializeModels() async {
    try {
      await _modelService.initialize();
    } on Object catch (_) {
      if (disposed) return;
      _hasModelStatusError = true;
      if (!disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_modelStatusSubscription?.cancel());
    super.dispose();
  }

  Future<void> downloadModel(String id) async {
    if (disposed) return;
    _actionError = null;
    try {
      await _modelService.downloadModel(id);
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.settingsSaveError ??
          'Unable to download this model. Please try again.';
      notifyListeners();
    }
  }

  Future<bool> deleteModel(String id) async {
    if (disposed) return false;
    _actionError = null;
    final model = _modelService.models.where((candidate) => candidate.id == id);
    if (model.isEmpty) return false;
    if (_dialogService != null) {
      final response = await _dialogService.showConfirmationDialog(
        title: _l10n?.deleteModelTitle ?? 'Delete model?',
        description:
            _l10n?.deleteModelDescription(model.first.name) ??
            'Remove ${model.first.name} and its local files?',
        confirmationTitle: _l10n?.deleteModelAction ?? 'Delete',
      );
      if (disposed) return false;
      if (response?.confirmed != true) return false;
    }
    try {
      final deleted = await _modelService.deleteModel(id);
      if (disposed) return false;
      if (!deleted) {
        _actionError =
            _l10n?.modelDeleteError ??
            'Unable to delete this model. Please try again.';
      }
      notifyListeners();
      return deleted;
    } on Object catch (_) {
      if (disposed) return false;
      _actionError =
          _l10n?.modelDeleteError ??
          'Unable to delete this model. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveToken(String token) async {
    if (disposed) return false;
    _actionError = null;
    try {
      await (_saveTokenAction ?? AuthTokenService.saveToken)(token);
      if (disposed) return false;
      _hasToken = true;
      notifyListeners();
      return true;
    } on Object catch (_) {
      if (disposed) return false;
      _actionError =
          _l10n?.tokenSaveError ??
          'Unable to save the token. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> clearToken() async {
    if (disposed) return;
    _actionError = null;
    try {
      await (_clearTokenAction ?? AuthTokenService.clearToken)();
      if (disposed) return;
      _hasToken = false;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.tokenClearError ??
          'Unable to clear the token. Please try again.';
    }
    _notifyIfAlive();
  }

  Future<bool> clearChatHistory() async {
    if (disposed) return false;
    _actionError = null;
    if (_dialogService != null) {
      final response = await _dialogService.showConfirmationDialog(
        title: _l10n?.clearChatHistoryTitle ?? 'Clear chat history?',
        description:
            _l10n?.clearChatHistoryDescription ??
            'Delete all locally saved conversations?',
        confirmationTitle: _l10n?.clearAction ?? 'Clear',
      );
      if (disposed) return false;
      if (response?.confirmed != true) return false;
    }
    try {
      await (_clearChatHistoryAction ??
          locator<ChatRepository>().clearHistory)();
      if (disposed) return false;
    } on Object catch (_) {
      if (disposed) return false;
      _actionError =
          _l10n?.chatHistoryClearError ??
          'Unable to clear chat history. Please try again.';
      _notifyIfAlive();
      return false;
    }
    _notifyIfAlive();
    return true;
  }

  Future<void> loadCrashLogs() async {
    if (disposed) return;
    _isLoadingCrashLogs = true;
    _actionError = null;
    _notifyIfAlive();
    try {
      final logs = await (_getCrashLogsAction ?? LoggingService.getCrashLogs)();
      if (disposed) return;
      _crashLogs = logs;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.crashLogsLoadError ??
          'Unable to load crash logs. Please try again.';
    } finally {
      if (!disposed) {
        _isLoadingCrashLogs = false;
        _notifyIfAlive();
      }
    }
  }

  Future<void> clearCrashLogs() async {
    if (disposed) return;
    _actionError = null;
    if (_dialogService != null) {
      final response = await _dialogService.showConfirmationDialog(
        title: _l10n?.clearCrashLogsTitle ?? 'Clear crash logs?',
        description:
            _l10n?.clearCrashLogsDescription ??
            'Delete all locally saved crash diagnostics?',
        confirmationTitle: _l10n?.clearAction ?? 'Clear',
      );
      if (disposed || response?.confirmed != true) return;
    }
    try {
      await (_clearCrashLogsAction ?? LoggingService.clearCrashLogs)();
      if (disposed) return;
      _crashLogs = [];
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.crashLogsClearError ??
          'Unable to clear crash logs. Please try again.';
    }
    _notifyIfAlive();
  }

  Future<void> enterToken() async {
    final dialogService = _dialogService;
    if (dialogService == null) return;
    _actionError = null;
    try {
      await dialogService.showCustomDialog<dynamic, dynamic>(
        variant: DialogType.tokenInput,
        data: const TokenInputDialogData(),
      );
      if (disposed) return;
      await _loadTokenState();
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.tokenSaveError ??
          'Unable to open token editor. Please try again.';
      notifyListeners();
    }
  }

  Future<void> exportCrashLogs() async {
    if (disposed) return;
    _actionError = null;
    try {
      await Clipboard.setData(ClipboardData(text: _crashLogs.join('\n')));
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.diagnosticsExportError ??
          'Unable to copy diagnostics. Please try again.';
      notifyListeners();
    }
  }

  // Model switching methods
  Future<void> switchInferenceModel(String modelId) async {
    if (disposed) return;
    _actionError = null;
    try {
      await _modelService.switchInferenceModel(modelId);
      if (disposed) return;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.settingsSaveError ??
          'Unable to save settings. Please try again.';
    }
    _notifyIfAlive();
  }

  Future<void> switchEmbeddingModel(String modelId) async {
    if (disposed) return;
    _actionError = null;
    final documentService = _documentService;
    if (documentService != null &&
        _modelService.activeEmbeddingModel?.id != modelId) {
      try {
        final documents = await documentService.getAllDocuments();
        if (disposed) return;
        final count = documents
            .where(
              (document) => document.needsReindex(modelId),
            )
            .length;
        if (count > 0 && _dialogService != null) {
          final response = await _dialogService.showConfirmationDialog(
            title: _l10n?.embeddingSwitchTitle ?? 'Change embedding model?',
            description:
                _l10n?.embeddingSwitchDescription(count) ??
                '$count document(s) will need to be re-indexed.',
            confirmationTitle: _l10n?.continueAction ?? 'Continue',
            cancelTitle: _l10n?.cancelAction ?? 'Cancel',
          );
          if (disposed) return;
          if (!(response?.confirmed ?? false)) return;
        }
      } on Object catch (_) {
        if (disposed) return;
        _actionError =
            _l10n?.embeddingStatusCheckError ??
            'Unable to check document index status.';
        notifyListeners();
        return;
      }
    }
    try {
      await _modelService.switchEmbeddingModel(modelId);
      if (disposed) return;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.settingsSaveError ??
          'Unable to save settings. Please try again.';
    }
    _notifyIfAlive();
  }

  // RAG Settings methods
  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleQueryExpansion(bool value) async {
    if (disposed) return;
    await _persist(
      () => _ragSettings.setQueryExpansionEnabled(value: value),
    );
    _notifyIfAlive();
  }

  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleReranking(bool value) async {
    if (disposed) return;
    await _persist(() => _ragSettings.setRerankingEnabled(value: value));
    _notifyIfAlive();
  }

  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleContextualRetrieval(bool value) async {
    if (disposed) return;
    await _persist(
      () => _ragSettings.setContextualRetrievalEnabled(value: value),
    );
    _notifyIfAlive();
  }

  void onChunkOverlapChanged(double value) {
    _chunkOverlapDragToken++;
    _pendingChunkOverlap = value;
    notifyListeners();
  }

  Future<void> onChunkOverlapChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _chunkOverlapDragToken;
    await _persist(() => _ragSettings.setChunkOverlapPercent(value / 100));
    if (disposed) return;
    if (_chunkOverlapDragToken == dragToken) {
      _pendingChunkOverlap = null;
    }
    _notifyIfAlive();
  }

  void onSemanticWeightChanged(double value) {
    _semanticWeightDragToken++;
    _pendingSemanticWeight = value;
    notifyListeners();
  }

  Future<void> onSemanticWeightChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _semanticWeightDragToken;
    await _persist(() => _ragSettings.setSemanticWeight(value));
    if (disposed) return;
    if (_semanticWeightDragToken == dragToken) {
      _pendingSemanticWeight = null;
    }
    _notifyIfAlive();
  }

  void onRerankTopKChanged(double value) {
    _rerankTopKDragToken++;
    _pendingRerankTopK = value;
    notifyListeners();
  }

  Future<void> onRerankTopKChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _rerankTopKDragToken;
    await _persist(() => _ragSettings.setRerankTopK(value.round()));
    if (disposed) return;
    if (_rerankTopKDragToken == dragToken) {
      _pendingRerankTopK = null;
    }
    _notifyIfAlive();
  }

  void onSearchTopKChanged(double value) {
    _searchTopKDragToken++;
    _pendingSearchTopK = value;
    notifyListeners();
  }

  Future<void> onSearchTopKChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _searchTopKDragToken;
    await _persist(() => _ragSettings.setSearchTopK(value.round()));
    if (disposed) return;
    if (_searchTopKDragToken == dragToken) {
      _pendingSearchTopK = null;
    }
    _notifyIfAlive();
  }

  void onMaxHistoryMessagesChanged(double value) {
    _maxHistoryMessagesDragToken++;
    _pendingMaxHistoryMessages = value;
    notifyListeners();
  }

  Future<void> onMaxHistoryMessagesChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _maxHistoryMessagesDragToken;
    await _persist(() => _ragSettings.setMaxHistoryMessages(value.round()));
    if (disposed) return;
    if (_maxHistoryMessagesDragToken == dragToken) {
      _pendingMaxHistoryMessages = null;
    }
    _notifyIfAlive();
  }

  void onMaxTokensChanged(double value) {
    _maxTokensDragToken++;
    _pendingMaxTokens = value;
    notifyListeners();
  }

  Future<void> onMaxTokensChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _maxTokensDragToken;
    final intValue = value.round();
    // If it matches model default, clear the override
    if (intValue == modelDefaultMaxTokens) {
      await _persist(() => _ragSettings.setMaxTokens(null));
    } else {
      await _persist(() => _ragSettings.setMaxTokens(intValue));
    }
    if (disposed) return;
    if (_maxTokensDragToken == dragToken) {
      _pendingMaxTokens = null;
    }
    _notifyIfAlive();
  }

  Future<void> setMaxDocumentSizeMB(double value) async {
    if (disposed) return;
    await _persist(() => _ragSettings.setMaxDocumentSizeMB(value.round()));
    _notifyIfAlive();
  }

  void onMaxDocumentSizeChanged(double value) {
    _maxDocumentSizeDragToken++;
    _pendingMaxDocumentSize = value;
    notifyListeners();
  }

  Future<void> onMaxDocumentSizeChangeEnd(double value) async {
    if (disposed) return;
    final dragToken = _maxDocumentSizeDragToken;
    await setMaxDocumentSizeMB(value);
    if (disposed) return;
    if (_maxDocumentSizeDragToken == dragToken) {
      _pendingMaxDocumentSize = null;
    }
    _notifyIfAlive();
  }

  Future<void> _persist(Future<void> Function() action) async {
    if (disposed) return;
    try {
      await action();
      if (disposed) return;
      _actionError = null;
    } on Object catch (_) {
      if (disposed) return;
      _actionError =
          _l10n?.settingsSaveError ??
          'Unable to save settings. Please try again.';
    }
    _notifyIfAlive();
  }

  Future<void> navigateToDocumentLibrary() async {
    if (disposed) return;
    await _navigationService.navigateTo<dynamic>(Routes.documentLibraryView);
  }

  void _notifyIfAlive() {
    if (!disposed) notifyListeners();
  }
}
