import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:stacked_services/stacked_services.dart';

class MockNavigationService extends Mock implements NavigationService {}

class MockModelManagementService extends Mock
    implements ModelManagementService {}

void registerTestHelpers() {
  _removeRegistrationIfExists<NavigationService>();
  _removeRegistrationIfExists<ModelManagementService>();

  locator
    ..registerSingleton<NavigationService>(MockNavigationService())
    ..registerSingleton<ModelManagementService>(
      MockModelManagementService(),
    );
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
  when(service.initialize).thenAnswer((_) => Future.value());

  return service;
}

Future<void> unregisterTestHelpers() async {
  await locator.reset();
}
