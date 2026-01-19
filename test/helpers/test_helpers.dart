import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/query_expansion_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/rag_token_manager.dart';
import 'package:offline_sync/services/reranking_service.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:stacked_services/stacked_services.dart';

class MockNavigationService extends Mock implements NavigationService {}

class MockModelManagementService extends Mock
    implements ModelManagementService {}

class MockRagSettingsService extends Mock implements RagSettingsService {}

class MockVectorStore extends Mock implements VectorStore {}

class MockInferenceModelProvider extends Mock
    implements InferenceModelProvider {}

class MockInferenceModel extends Mock implements InferenceModel {}

class MockQueryExpansionService extends Mock implements QueryExpansionService {}

class MockRerankingService extends Mock implements RerankingService {}

class MockRagTokenManager extends Mock implements RagTokenManager {}

class MockEmbeddingService extends Mock implements EmbeddingService {}

void registerTestHelpers() {
  _removeRegistrationIfExists<RerankingService>();
  _removeRegistrationIfExists<EmbeddingService>();

  locator
    ..registerSingleton<NavigationService>(MockNavigationService())
    ..registerSingleton<ModelManagementService>(
      MockModelManagementService(),
    )
    ..registerSingleton<RagSettingsService>(MockRagSettingsService())
    ..registerSingleton<VectorStore>(MockVectorStore())
    ..registerSingleton<InferenceModelProvider>(MockInferenceModelProvider())
    ..registerSingleton<QueryExpansionService>(MockQueryExpansionService())
    ..registerSingleton<RerankingService>(MockRerankingService())
    ..registerSingleton<EmbeddingService>(MockEmbeddingService())
    ..registerSingleton<RagTokenManager>(MockRagTokenManager());
}

void _removeRegistrationIfExists<T extends Object>() {
  if (locator.isRegistered<T>()) {
    locator.unregister<T>();
  }
}

MockNavigationService getAndRegisterMockNavigationService() {
  _removeRegistrationIfExists<NavigationService>();
  final service = MockNavigationService();
  locator.registerSingleton<NavigationService>(service);
  return service;
}

MockModelManagementService getAndRegisterMockModelManagementService() {
  _removeRegistrationIfExists<ModelManagementService>();
  final service = MockModelManagementService();
  locator.registerSingleton<ModelManagementService>(service);

  // Default simple mock behaviors
  when(() => service.models).thenReturn([]);
  when(() => service.modelStatusStream).thenAnswer((_) => const Stream.empty());
  when(service.initialize).thenAnswer((_) async {});
  when(() => service.downloadModel(any())).thenAnswer((_) => Future.value());

  return service;
}

MockRagSettingsService getAndRegisterMockRagSettingsService() {
  _removeRegistrationIfExists<RagSettingsService>();
  final service = MockRagSettingsService();
  locator.registerSingleton<RagSettingsService>(service);

  // Default mock behaviors
  when(() => service.queryExpansionEnabled).thenReturn(false);
  when(() => service.rerankingEnabled).thenReturn(false);
  when(() => service.chunkOverlapPercent).thenReturn(0.15);
  when(() => service.semanticWeight).thenReturn(0.7);
  when(() => service.rerankTopK).thenReturn(10);
  when(() => service.searchTopK).thenReturn(5);
  when(() => service.maxHistoryMessages).thenReturn(10);
  when(() => service.contextualRetrievalEnabled).thenReturn(false);
  when(service.initialize).thenAnswer((_) async {});

  return service;
}

MockVectorStore getAndRegisterMockVectorStore() {
  _removeRegistrationIfExists<VectorStore>();
  final service = MockVectorStore();
  locator.registerSingleton<VectorStore>(service);
  return service;
}

MockRagTokenManager getAndRegisterMockRagTokenManager() {
  _removeRegistrationIfExists<RagTokenManager>();
  final service = MockRagTokenManager();

  // Default behavior
  when(() => service.estimateTokens(any())).thenAnswer((invocation) {
    final text = invocation.positionalArguments[0] as String;
    return (text.length / 4).ceil();
  });

  when(() => service.buildHistoryWithBudget(any(), any())).thenAnswer((
    invocation,
  ) {
    final history = invocation.positionalArguments[0] as List<String>;
    final budget = invocation.positionalArguments[1] as int;

    // Simple mock implementation similar to real one
    if (history.isEmpty) return '';
    final recentCount = history.length >= 2 ? 2 : history.length;
    final recent = history.sublist(history.length - recentCount);
    var tokens = (recent.join('\n').length / 4).ceil();
    final limited = <String>[...recent];
    for (var i = history.length - recentCount - 1; i >= 0; i--) {
      final msg = history[i];
      final msgTokens = (msg.length / 4).ceil();
      if (tokens + msgTokens <= budget) {
        limited.insert(0, msg);
        tokens += msgTokens;
      } else {
        break;
      }
    }
    return 'Previous conversation:\n${limited.join('\n')}\n\n';
  });

  locator.registerSingleton<RagTokenManager>(service);
  return service;
}

MockInferenceModelProvider getAndRegisterMockInferenceModelProvider() {
  _removeRegistrationIfExists<InferenceModelProvider>();
  final service = MockInferenceModelProvider();
  locator.registerSingleton<InferenceModelProvider>(service);
  return service;
}

MockQueryExpansionService getAndRegisterMockQueryExpansionService() {
  _removeRegistrationIfExists<QueryExpansionService>();
  final service = MockQueryExpansionService();
  locator.registerSingleton<QueryExpansionService>(service);
  return service;
}

MockRerankingService getAndRegisterMockRerankingService() {
  _removeRegistrationIfExists<RerankingService>();
  final service = MockRerankingService();
  locator.registerSingleton<RerankingService>(service);
  return service;
}

MockEmbeddingService getAndRegisterMockEmbeddingService() {
  _removeRegistrationIfExists<EmbeddingService>();
  final service = MockEmbeddingService();
  locator.registerSingleton<EmbeddingService>(service);
  return service;
}

Future<void> unregisterTestHelpers() async {
  await locator.reset();
}
