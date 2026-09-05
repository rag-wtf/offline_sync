import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/auth_token_service.dart';
import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/device_capability_service.dart';
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
  }) : _modelService = modelService ?? locator<ModelManagementService>(),
       _ragSettings = ragSettings ?? locator<RagSettingsService>(),
       _navigationService = navigationService ?? locator<NavigationService>(),
       _deviceService = deviceService ?? locator<DeviceCapabilityService>();

  final ModelManagementService _modelService;
  final RagSettingsService _ragSettings;
  final NavigationService _navigationService;
  final DeviceCapabilityService _deviceService;

  DeviceCapabilities? _capabilities;
  double? _pendingChunkOverlap;
  double? _pendingSemanticWeight;
  double? _pendingSearchTopK;
  double? _pendingMaxHistoryMessages;
  double? _pendingMaxTokens;
  int _chunkOverlapDragToken = 0;
  int _semanticWeightDragToken = 0;
  int _searchTopKDragToken = 0;
  int _maxHistoryMessagesDragToken = 0;
  int _maxTokensDragToken = 0;
  Object? _modelStatusError;
  String? _settingsError;
  List<String> _crashLogs = const [];
  bool? _hasToken;

  DeviceCapabilities? get capabilities => _capabilities;
  bool get hasModelStatusError => _modelStatusError != null;
  String? get settingsError => _settingsError;
  List<String> get crashLogs => _crashLogs;
  bool? get hasToken => _hasToken;

  AppLocalizations? get _l10n {
    final context = StackedService.navigatorKey?.currentContext;
    return context == null
        ? null
        : Localizations.of<AppLocalizations>(context, AppLocalizations);
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
  int get maxDocumentSizeMB => _ragSettings.maxDocumentSizeMB;
  double get chunkOverlapDisplay =>
      _pendingChunkOverlap ?? (_ragSettings.chunkOverlapPercent * 100);
  double get semanticWeightDisplay =>
      _pendingSemanticWeight ?? _ragSettings.semanticWeight;
  double get searchTopKDisplay =>
      _pendingSearchTopK ?? _ragSettings.searchTopK.toDouble();
  double get maxHistoryMessagesDisplay =>
      _pendingMaxHistoryMessages ?? _ragSettings.maxHistoryMessages.toDouble();
  double get maxTokensDisplay => _pendingMaxTokens ?? maxTokens.toDouble();
  double get maxTokensLimit =>
      _ragSettings.activeInferenceContextLimit.toDouble();

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
        _modelStatusError = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        _modelStatusError = error;
        notifyListeners();
      },
    );
    unawaited(_initializeModels());
    unawaited(_loadCrashLogs());
    unawaited(_loadTokenState());
    // Load device capabilities
    unawaited(_loadDeviceCapabilities());
  }

  Future<void> _loadTokenState() async {
    try {
      _hasToken = await AuthTokenService.hasToken();
    } on Object catch (error) {
      _settingsError = 'Unable to read token status (${error.runtimeType}).';
    }
    notifyListeners();
  }

  Future<void> _initializeModels() async {
    try {
      await _modelService.initialize();
    } on Object catch (error, stackTrace) {
      _modelStatusError = error;
      LoggingService.warning(
        'Model initialization failed (${error.runtimeType})',
        name: 'SettingsViewModel',
      );
      if (!disposed) notifyListeners();
      // Expected startup failures are represented in state, not rethrown from
      // an unawaited callback.
      LoggingService.debug('Model initialization stack: $stackTrace');
    }
  }

  Future<void> _loadCrashLogs() async {
    try {
      _crashLogs = await LoggingService.getCrashLogs();
    } on Object catch (error) {
      _settingsError = 'Unable to load diagnostics (${error.runtimeType}).';
    }
    if (!disposed) notifyListeners();
  }

  Future<void> _loadDeviceCapabilities() async {
    try {
      _capabilities = await _deviceService.getCapabilities();
      LoggingService.debug('Settings device capabilities loaded');
    } on Object catch (error) {
      LoggingService.debug('Settings device capability load failed');
      _settingsError =
          'Unable to load device information (${error.runtimeType}).';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_modelStatusSubscription?.cancel());
    super.dispose();
  }

  Future<void> downloadModel(String id) async {
    await _modelService.downloadModel(id);
  }

  // Model switching methods
  Future<void> switchInferenceModel(String modelId) async {
    try {
      await _modelService.switchInferenceModel(modelId);
      _settingsError = null;
    } on Object catch (error) {
      _settingsError = 'Unable to switch model (${error.runtimeType}).';
    }
    notifyListeners();
  }

  Future<void> switchEmbeddingModel(String modelId) async {
    try {
      await _modelService.switchEmbeddingModel(modelId);
      _settingsError = null;
    } on Object catch (error) {
      _settingsError = 'Unable to switch model (${error.runtimeType}).';
    }
    notifyListeners();
  }

  // RAG Settings methods
  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleQueryExpansion(bool value) async {
    await _persist(() => _ragSettings.setQueryExpansionEnabled(value: value));
    notifyListeners();
  }

  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleReranking(bool value) async {
    await _persist(() => _ragSettings.setRerankingEnabled(value: value));
    notifyListeners();
  }

  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleContextualRetrieval(bool value) async {
    await _persist(
      () => _ragSettings.setContextualRetrievalEnabled(value: value),
    );
    notifyListeners();
  }

  void onChunkOverlapChanged(double value) {
    _chunkOverlapDragToken++;
    _pendingChunkOverlap = value;
    notifyListeners();
  }

  Future<void> onChunkOverlapChangeEnd(double value) async {
    final dragToken = _chunkOverlapDragToken;
    if (await _persist(
      () => _ragSettings.setChunkOverlapPercent(value / 100),
    )) {
      if (_chunkOverlapDragToken == dragToken) _pendingChunkOverlap = null;
    }
    notifyListeners();
  }

  void onSemanticWeightChanged(double value) {
    _semanticWeightDragToken++;
    _pendingSemanticWeight = value;
    notifyListeners();
  }

  Future<void> onSemanticWeightChangeEnd(double value) async {
    final dragToken = _semanticWeightDragToken;
    if (await _persist(() => _ragSettings.setSemanticWeight(value))) {
      if (_semanticWeightDragToken == dragToken) _pendingSemanticWeight = null;
    }
    notifyListeners();
  }

  void onSearchTopKChanged(double value) {
    _searchTopKDragToken++;
    _pendingSearchTopK = value;
    notifyListeners();
  }

  Future<void> onSearchTopKChangeEnd(double value) async {
    final dragToken = _searchTopKDragToken;
    if (await _persist(() => _ragSettings.setSearchTopK(value.round()))) {
      if (_searchTopKDragToken == dragToken) _pendingSearchTopK = null;
    }
    notifyListeners();
  }

  void onMaxHistoryMessagesChanged(double value) {
    _maxHistoryMessagesDragToken++;
    _pendingMaxHistoryMessages = value;
    notifyListeners();
  }

  Future<void> onMaxHistoryMessagesChangeEnd(double value) async {
    final dragToken = _maxHistoryMessagesDragToken;
    if (await _persist(
      () => _ragSettings.setMaxHistoryMessages(value.round()),
    )) {
      if (_maxHistoryMessagesDragToken == dragToken) {
        _pendingMaxHistoryMessages = null;
      }
    }
    notifyListeners();
  }

  void onMaxTokensChanged(double value) {
    _maxTokensDragToken++;
    _pendingMaxTokens = value;
    notifyListeners();
  }

  Future<void> onMaxTokensChangeEnd(double value) async {
    final dragToken = _maxTokensDragToken;
    final intValue = value.round();
    // If it matches model default, clear the override
    final succeeded = intValue == modelDefaultMaxTokens
        ? await _persist(() => _ragSettings.setMaxTokens(null))
        : await _persist(() => _ragSettings.setMaxTokens(intValue));
    if (succeeded) {
      if (_maxTokensDragToken == dragToken) _pendingMaxTokens = null;
    }
    notifyListeners();
  }

  Future<bool> deleteModel(ModelInfo model) async {
    final response = await locator<DialogService>().showConfirmationDialog(
      title: _l10n?.deleteModelTitle ?? 'Delete model?',
      description:
          _l10n?.deleteModelDescription(model.name) ??
          'Remove ${model.name} and its local files?',
      confirmationTitle: _l10n?.deleteModelAction ?? 'Delete',
    );
    if (response?.confirmed != true) return false;
    try {
      final deleted = await _modelService.deleteModel(model.id);
      if (!deleted) _settingsError = 'Unable to delete model.';
      return deleted;
    } on Object catch (error) {
      _settingsError = 'Unable to delete model (${error.runtimeType}).';
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> enterToken() async {
    try {
      await locator<DialogService>().showCustomDialog<dynamic, dynamic>(
        variant: DialogType.tokenInput,
        data: const TokenInputDialogData(),
      );
      await _loadTokenState();
    } on Object catch (error) {
      _settingsError = 'Unable to open token editor (${error.runtimeType}).';
      notifyListeners();
    }
  }

  Future<void> clearToken() async {
    try {
      await AuthTokenService.clearToken();
      _hasToken = false;
      _settingsError = null;
    } on Object catch (error) {
      _settingsError = 'Unable to clear token (${error.runtimeType}).';
    }
    notifyListeners();
  }

  Future<void> exportCrashLogs() async {
    await Clipboard.setData(ClipboardData(text: _crashLogs.join('\n')));
  }

  Future<void> clearCrashLogs() async {
    try {
      await LoggingService.clearCrashLogs();
      _crashLogs = const [];
    } on Object catch (error) {
      _settingsError = 'Unable to clear diagnostics (${error.runtimeType}).';
    }
    notifyListeners();
  }

  Future<bool> clearChatHistory() async {
    if (!locator.isRegistered<ChatRepository>()) return false;
    final response = await locator<DialogService>().showConfirmationDialog(
      title: _l10n?.clearChatHistoryTitle ?? 'Clear chat history?',
      description:
          _l10n?.clearChatHistoryDescription ??
          'Delete all locally saved conversations?',
      confirmationTitle: _l10n?.clearAction ?? 'Clear',
    );
    if (response?.confirmed != true) return false;
    try {
      await locator<ChatRepository>().clearHistory();
      _settingsError = null;
      return true;
    } on Object catch (error) {
      _settingsError = 'Unable to clear chat history (${error.runtimeType}).';
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> _persist(Future<void> Function() operation) async {
    try {
      await operation();
      _settingsError = null;
      return true;
    } on Object catch (error) {
      _settingsError = 'Unable to save setting (${error.runtimeType}).';
      return false;
    }
  }

  Future<void> navigateToDocumentLibrary() async {
    await _navigationService.navigateTo<dynamic>(Routes.documentLibraryView);
  }
}
