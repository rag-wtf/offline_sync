import 'dart:async';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:stacked/stacked.dart';

class SettingsViewModel extends BaseViewModel {
  final ModelManagementService _modelService =
      locator<ModelManagementService>();
  final RagSettingsService _ragSettings = locator<RagSettingsService>();

  List<ModelInfo> get models => _modelService.models;

  // RAG Settings getters
  bool get queryExpansionEnabled => _ragSettings.queryExpansionEnabled;
  bool get rerankingEnabled => _ragSettings.rerankingEnabled;
  double get chunkOverlapPercent => _ragSettings.chunkOverlapPercent * 100;
  double get semanticWeight => _ragSettings.semanticWeight;

  void setup() {
    _modelService.modelStatusStream.listen((_) => notifyListeners());
    unawaited(_modelService.initialize());
  }

  Future<void> downloadModel(String id) async {
    await _modelService.downloadModel(id);
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
}
