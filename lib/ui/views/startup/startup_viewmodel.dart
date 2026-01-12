import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class StartupViewModel extends BaseViewModel {
  final _navigationService = locator<NavigationService>();
  final _modelService = locator<ModelManagementService>();

  Future<void> runStartupLogic() async {
    await _modelService.initialize();

    final hasModels = _modelService.models.any(
      (m) => m.status == ModelStatus.downloaded,
    );

    if (hasModels) {
      await _navigationService.replaceWithChatView();
    } else {
      await _navigationService.replaceWithSettingsView();
    }
  }
}
