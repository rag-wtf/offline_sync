// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// StackedLocatorGenerator
// **************************************************************************

// ignore_for_file: public_member_api_docs, implementation_imports, depend_on_referenced_packages

import 'package:stacked_services/src/dialog/dialog_service.dart';
import 'package:stacked_services/src/navigation/navigation_service.dart';
import 'package:stacked_services/src/snackbar/snackbar_service.dart';
import 'package:stacked_shared/stacked_shared.dart';

import '../services/chat_repository.dart';
import '../services/contextual_retrieval_service.dart';
import '../services/device_capability_service.dart';
import '../services/document_management_service.dart';
import '../services/document_parser_service.dart';
import '../services/embedding_service.dart';
import '../services/environment_service.dart';
import '../services/model_management_service.dart';
import '../services/model_recommendation_service.dart';
import '../services/query_expansion_service.dart';
import '../services/rag_service.dart';
import '../services/rag_settings_service.dart';
import '../services/reranking_service.dart';
import '../services/smart_chunker.dart';
import '../services/vector_store.dart';

final locator = StackedLocator.instance;

Future<void> setupLocator({
  String? environment,
  EnvironmentFilter? environmentFilter,
}) async {
  // Register environments
  locator.registerEnvironment(
    environment: environment,
    environmentFilter: environmentFilter,
  );

  // Register dependencies
  locator.registerLazySingleton(() => NavigationService());
  locator.registerLazySingleton(() => DialogService());
  locator.registerLazySingleton(() => SnackbarService());
  locator.registerLazySingleton(() => EnvironmentService());
  locator.registerLazySingleton(() => VectorStore());
  locator.registerLazySingleton(() => ChatRepository());
  locator.registerLazySingleton(() => ModelManagementService());
  locator.registerLazySingleton(() => EmbeddingService());
  locator.registerLazySingleton(() => RagService());
  locator.registerLazySingleton(() => RagSettingsService());
  locator.registerLazySingleton(() => QueryExpansionService());
  locator.registerLazySingleton(() => RerankingService());
  locator.registerLazySingleton(() => DocumentParserService());
  locator.registerLazySingleton(() => SmartChunker());
  locator.registerLazySingleton(() => DocumentManagementService());
  locator.registerLazySingleton(() => DeviceCapabilityService());
  locator.registerLazySingleton(() => ContextualRetrievalService());
  locator.registerLazySingleton(() => ModelRecommendationService());
}
