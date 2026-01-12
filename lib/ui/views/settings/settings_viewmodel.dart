import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:stacked/stacked.dart';

class SettingsViewModel extends BaseViewModel {
  final _modelService = locator<ModelManagementService>();

  List<ModelInfo> get models => _modelService.models;

  void setup() {
    _modelService.modelStatusStream.listen((_) => notifyListeners());
    _modelService.initialize();
  }

  Future<void> downloadModel(String id) async {
    await _modelService.downloadModel(id);
  }
}
