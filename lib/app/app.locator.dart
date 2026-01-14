// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// StackedLocatorGenerator
// **************************************************************************

// ignore_for_file: public_member_api_docs, implementation_imports, depend_on_referenced_packages

import 'package:stacked_services/src/navigation/navigation_service.dart';
import 'package:stacked_services/src/snackbar/snackbar_service.dart';
import 'package:stacked_shared/stacked_shared.dart';

import '../services/chat_repository.dart';
import '../services/embedding_service.dart';
import '../services/model_management_service.dart';
import '../services/rag_service.dart';
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
  locator.registerLazySingleton(() => SnackbarService());
  locator.registerLazySingleton(() => VectorStore());
  locator.registerLazySingleton(() => ChatRepository());
  locator.registerLazySingleton(() => ModelManagementService());
  locator.registerLazySingleton(() => EmbeddingService());
  locator.registerLazySingleton(() => RagService());
}
