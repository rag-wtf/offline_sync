import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_view.dart';
import 'package:offline_sync/ui/views/settings/settings_view.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';

@StackedApp(
  routes: [
    MaterialRoute(page: StartupView, initial: true),
    MaterialRoute(page: ChatView),
    MaterialRoute(page: SettingsView),
  ],
  dependencies: [
    LazySingleton<NavigationService>(classType: NavigationService),
    LazySingleton<SnackbarService>(classType: SnackbarService),
    LazySingleton<VectorStore>(classType: VectorStore),
    LazySingleton<ModelManagementService>(classType: ModelManagementService),
    LazySingleton<EmbeddingService>(classType: EmbeddingService),
    LazySingleton<RagService>(classType: RagService),
  ],

  logger: StackedLogger(),
)
class App {}
