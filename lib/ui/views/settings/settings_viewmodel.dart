import 'dart:async';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class SettingsViewModel extends BaseViewModel {
  final ModelManagementService _modelService =
      locator<ModelManagementService>();
  final RagSettingsService _ragSettings = locator<RagSettingsService>();
  final NavigationService _navigationService = locator<NavigationService>();
  final DeviceCapabilityService _deviceService = DeviceCapabilityService();

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

  DeviceCapabilities? get capabilities => _capabilities;

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
  double get searchTopKDisplay =>
      _pendingSearchTopK ?? _ragSettings.searchTopK.toDouble();
  double get maxHistoryMessagesDisplay =>
      _pendingMaxHistoryMessages ?? _ragSettings.maxHistoryMessages.toDouble();
  double get maxTokensDisplay => _pendingMaxTokens ?? maxTokens.toDouble();

  // Get user-configured maxTokens or model default
  int get maxTokens {
    final userValue = _ragSettings.maxTokens;
    if (userValue != null) return userValue;

    // Return model default
    return ModelConfig.allModels
        .firstWhere(
          (m) => m.type == AppModelType.inference,
          orElse: () => InferenceModels.gemma3_270M,
        )
        .maxTokens;
  }

  // Get the model's default maxTokens for display
  int get modelDefaultMaxTokens {
    return ModelConfig.allModels
        .firstWhere(
          (m) => m.type == AppModelType.inference,
          orElse: () => InferenceModels.gemma3_270M,
        )
        .maxTokens;
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
      (_) => notifyListeners(),
    );
    unawaited(_modelService.initialize());
    // Load device capabilities
    unawaited(_loadDeviceCapabilities());
  }

  Future<void> _loadDeviceCapabilities() async {
    _capabilities = await _deviceService.getCapabilities();
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
    await _modelService.switchInferenceModel(modelId);
    notifyListeners();
  }

  Future<void> switchEmbeddingModel(String modelId) async {
    await _modelService.switchEmbeddingModel(modelId);
    notifyListeners();
  }

  // RAG Settings methods
  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleQueryExpansion(bool value) async {
    await _ragSettings.setQueryExpansionEnabled(value: value);
    notifyListeners();
  }

  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleReranking(bool value) async {
    await _ragSettings.setRerankingEnabled(value: value);
    notifyListeners();
  }

  // Positional bool required by SwitchListTile.onChanged callback signature
  // ignore: avoid_positional_boolean_parameters
  Future<void> toggleContextualRetrieval(bool value) async {
    await _ragSettings.setContextualRetrievalEnabled(value: value);
    notifyListeners();
  }

  void onChunkOverlapChanged(double value) {
    _chunkOverlapDragToken++;
    _pendingChunkOverlap = value;
    notifyListeners();
  }

  Future<void> onChunkOverlapChangeEnd(double value) async {
    final dragToken = _chunkOverlapDragToken;
    await _ragSettings.setChunkOverlapPercent(value / 100);
    if (_chunkOverlapDragToken == dragToken) {
      _pendingChunkOverlap = null;
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
    await _ragSettings.setSemanticWeight(value);
    if (_semanticWeightDragToken == dragToken) {
      _pendingSemanticWeight = null;
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
    await _ragSettings.setSearchTopK(value.round());
    if (_searchTopKDragToken == dragToken) {
      _pendingSearchTopK = null;
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
    await _ragSettings.setMaxHistoryMessages(value.round());
    if (_maxHistoryMessagesDragToken == dragToken) {
      _pendingMaxHistoryMessages = null;
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
    if (intValue == modelDefaultMaxTokens) {
      await _ragSettings.setMaxTokens(null);
    } else {
      await _ragSettings.setMaxTokens(intValue);
    }
    if (_maxTokensDragToken == dragToken) {
      _pendingMaxTokens = null;
    }
    notifyListeners();
  }

  Future<void> navigateToDocumentLibrary() async {
    await _navigationService.navigateTo<dynamic>(Routes.documentLibraryView);
  }
}
