import 'package:offline_sync/services/chat_repository.dart';
import 'package:offline_sync/services/contextual_retrieval_service.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/environment_service.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/services/query_expansion_service.dart';
import 'package:offline_sync/services/rag_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/reranking_service.dart';
import 'package:offline_sync/services/smart_chunker.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:offline_sync/ui/views/chat/chat_view.dart';
import 'package:offline_sync/ui/views/document_detail/document_detail_view.dart';
import 'package:offline_sync/ui/views/document_library/document_library_view.dart';
import 'package:offline_sync/ui/views/settings/settings_view.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';
import 'package:stacked/stacked_annotations.dart';
import 'package:stacked_services/stacked_services.dart';

@StackedApp(
  routes: [
    MaterialRoute(page: StartupView, initial: true),
    MaterialRoute(page: ChatView),
    MaterialRoute(page: SettingsView),
    MaterialRoute(page: DocumentLibraryView),
    MaterialRoute(page: DocumentDetailView),
  ],
  dependencies: [
    LazySingleton<NavigationService>(classType: NavigationService),
    LazySingleton<SnackbarService>(classType: SnackbarService),
    LazySingleton<EnvironmentService>(classType: EnvironmentService),
    LazySingleton<VectorStore>(classType: VectorStore),
    LazySingleton<ChatRepository>(classType: ChatRepository),
    LazySingleton<ModelManagementService>(classType: ModelManagementService),
    LazySingleton<EmbeddingService>(classType: EmbeddingService),
    LazySingleton<RagService>(classType: RagService),
    LazySingleton<RagSettingsService>(classType: RagSettingsService),
    LazySingleton<QueryExpansionService>(classType: QueryExpansionService),
    LazySingleton<RerankingService>(classType: RerankingService),
    LazySingleton<DocumentParserService>(classType: DocumentParserService),
    LazySingleton<SmartChunker>(classType: SmartChunker),
    LazySingleton<DocumentManagementService>(
      classType: DocumentManagementService,
    ),
    LazySingleton<DeviceCapabilityService>(classType: DeviceCapabilityService),
    LazySingleton<ContextualRetrievalService>(
      classType: ContextualRetrievalService,
    ),
    LazySingleton<ModelRecommendationService>(
      classType: ModelRecommendationService,
    ),
  ],

  logger: StackedLogger(),
)
class App {}
