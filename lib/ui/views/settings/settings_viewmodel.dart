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
  double get chunkOverlapPercent => _ragSettings.chunkOverlapPercent * 100;
  double get semanticWeight => _ragSettings.semanticWeight;
  int get searchTopK => _ragSettings.searchTopK;
  int get maxHistoryMessages => _ragSettings.maxHistoryMessages;

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

  Future<void> setChunkOverlap(double value) async {
    await _ragSettings.setChunkOverlapPercent(
      value / 100,
    ); // Convert % to decimal
    notifyListeners();
  }

  Future<void> setSemanticWeight(double value) async {
    await _ragSettings.setSemanticWeight(value);
    notifyListeners();
  }

  Future<void> setSearchTopK(double value) async {
    await _ragSettings.setSearchTopK(value.round());
    notifyListeners();
  }

  Future<void> setMaxHistoryMessages(double value) async {
    await _ragSettings.setMaxHistoryMessages(value.round());
    notifyListeners();
  }

  Future<void> setMaxTokens(double value) async {
    final intValue = value.round();
    // If it matches model default, clear the override
    if (intValue == modelDefaultMaxTokens) {
      await _ragSettings.setMaxTokens(null);
    } else {
      await _ragSettings.setMaxTokens(intValue);
    }
    notifyListeners();
  }

  Future<void> navigateToDocumentLibrary() async {
    await _navigationService.navigateTo<dynamic>(Routes.documentLibraryView);
  }
}
