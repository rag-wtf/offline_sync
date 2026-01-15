import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:stacked_services/stacked_services.dart';

class MockNavigationService extends Mock implements NavigationService {}

class MockModelManagementService extends Mock
    implements ModelManagementService {}

class MockRagSettingsService extends Mock implements RagSettingsService {}

void registerTestHelpers() {
  _removeRegistrationIfExists<NavigationService>();
  _removeRegistrationIfExists<ModelManagementService>();
  _removeRegistrationIfExists<RagSettingsService>();

  locator
    ..registerSingleton<NavigationService>(MockNavigationService())
    ..registerSingleton<ModelManagementService>(
      MockModelManagementService(),
    )
    ..registerSingleton<RagSettingsService>(MockRagSettingsService());
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
  when(service.initialize).thenAnswer((_) async {});

  return service;
}

Future<void> unregisterTestHelpers() async {
  await locator.reset();
}
