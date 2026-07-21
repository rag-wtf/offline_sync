import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

class FakeDeviceCapabilityService extends DeviceCapabilityService {
  FakeDeviceCapabilityService(this.value);

  final DeviceCapabilities value;

  @override
  Future<DeviceCapabilities> getCapabilities() async => value;
}

class FakeModelRecommendationService extends ModelRecommendationService {
  @override
  RecommendedModels getRecommendedModels(DeviceCapabilities capabilities) {
    return const RecommendedModels(
      inferenceModel: InferenceModels.gemma3_270M,
      embeddingModel: EmbeddingModels.gecko64,
      tier: DeviceTier.low,
    );
  }
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.single.physicalSize = const Size(
      1200,
      1000,
    );
    binding.platformDispatcher.views.single.devicePixelRatio = 1;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.single.resetPhysicalSize();
    binding.platformDispatcher.views.single.resetDevicePixelRatio();
  });

  Widget buildSubject(StartupViewModel viewModel) {
    return MaterialApp(
      home: StartupView(
        viewModel: viewModel,
        onViewModelReadyCallback: (_) {},
      ),
    );
  }

  testWidgets('renders the initial loading state', (tester) async {
    final viewModel = StartupViewModel(
      navigationService: MockNavigationService(),
      modelService: MockModelManagementService(),
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 2048,
          availableStorageMB: 512,
          hasGpu: false,
          platform: 'linux',
        ),
      ),
      recommendationService: FakeModelRecommendationService(),
    );

    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.text('OfflineSync RAG'), findsOneWidget);
    expect(find.text('On-device AI with your documents'), findsOneWidget);
    expect(find.text('Initializing AI Models...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders status and device information in loading state', (
    tester,
  ) async {
    final modelService = MockModelManagementService();
    final viewModel = StartupViewModel(
      navigationService: MockNavigationService(),
      modelService: modelService,
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 2048,
          availableStorageMB: 512,
          hasGpu: true,
          platform: 'linux',
        ),
      ),
      recommendationService: FakeModelRecommendationService(),
    );
    when(
      () => modelService.modelStatusStream,
    ).thenAnswer((_) => const Stream.empty());
    when(modelService.initialize).thenThrow(Exception('model failure'));

    await viewModel.runStartupLogic();
    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.text('Selecting optimal models...'), findsOneWidget);
    expect(find.text('Device Information'), findsOneWidget);
    expect(find.text('2.0 GB'), findsOneWidget);
    expect(find.text('512 MB'), findsOneWidget);
    expect(find.text('linux'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('renders error state with retry action', (tester) async {
    final viewModel = StartupViewModel(
      navigationService: MockNavigationService(),
      modelService: MockModelManagementService(),
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 1024,
          availableStorageMB: 2048,
          hasGpu: false,
          platform: 'android',
        ),
      ),
      recommendationService: FakeModelRecommendationService(),
    )..setError('Initialization failed');

    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.text('Initialization failed'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Enter Token'), findsNothing);
  });
}
