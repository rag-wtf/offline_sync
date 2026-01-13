import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/dialogs/token_input_dialog.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class StartupViewModel extends BaseViewModel {
  final _navigationService = locator<NavigationService>();
  final _modelService = locator<ModelManagementService>();

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  bool _needsToken = false;
  bool get needsToken => _needsToken;

  Future<void> runStartupLogic() async {
    _modelService.modelStatusStream.listen(
      (models) {
        final downloading = models.where(
          (m) => m.status == ModelStatus.downloading,
        );
        if (downloading.isNotEmpty) {
          final m = downloading.first;
          final progress = (m.progress * 100).toStringAsFixed(1);
          _statusMessage = 'Downloading ${m.name}: $progress%';
          notifyListeners();
        } else {
          final error = models.where((m) => m.status == ModelStatus.error);
          if (error.isNotEmpty) {
            // Check if any of the errors indicate a 401
            final has401Error = error.any(
              (m) => m.errorMessage?.contains('401') ?? false,
            );

            if (has401Error) {
              _needsToken = true;
              _statusMessage = 'Authentication Required';
              setError('Missing or invalid Hugging Face Token.');
            } else {
              _statusMessage = 'Error downloading models.';
              setError('Check internet connection or storage.');
            }
          } else {
            _statusMessage = 'Finalizing initialization...';
            notifyListeners();
          }
        }
      },
      onError: (Object e) {
        final msg = e.toString();
        if (msg.contains('401')) {
          _needsToken = true;
          setError('Authentication Failed (401)');
        } else {
          setError(msg);
        }
      },
    );

    try {
      await _modelService.initialize();

      // Check if any critical errors occurred during initialize (that weren't caught/handled fully)
      final errors = _modelService.models.where(
        (m) => m.status == ModelStatus.error,
      );
      if (errors.isNotEmpty) {
        // If 401 was already caught by listener, fine.
        // Otherwise set generic error.
        if (errors.any((m) => m.errorMessage?.contains('401') ?? false)) {
          _needsToken = true;
          setError('Missing or invalid Hugging Face Token.');
        } else if (!hasError) {
          setError('Failed to download models. Please retry.');
        }
        return;
      }

      await _checkAndNavigate();
    } on Object catch (e) {
      setError(e.toString());
    }
  }

  Future<void> _checkAndNavigate() async {
    final hasModels = _modelService.models.any(
      (m) => m.status == ModelStatus.downloaded,
    );

    if (hasModels) {
      final hasInferenceModel = _modelService.models.any(
        (m) => m.type == 'inference' && m.status == ModelStatus.downloaded,
      );

      if (hasInferenceModel) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _navigationService.replaceWithChatView();
      } else {
        await _navigationService.replaceWithSettingsView();
      }
    } else {
      await _navigationService.replaceWithSettingsView();
    }
  }

  Future<void> retry() async {
    setError(null);
    _needsToken = false;
    _statusMessage = 'Retrying...';
    notifyListeners();
    await runStartupLogic();
  }

  Future<void> enterToken() async {
    await _navigationService.navigateWithTransition<bool?>(
      const TokenInputDialog(),
      transitionStyle: Transition.fade,
    );
    await retry();
  }
}
