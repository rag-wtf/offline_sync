import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/download_policy_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/services/model_recommendation_service.dart';
import 'package:offline_sync/ui/views/startup/startup_view.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

class FakeDeviceCapabilityService extends DeviceCapabilityService {
  FakeDeviceCapabilityService(this.value);

  final DeviceCapabilities value;

  @override
  Future<DeviceCapabilities> getCapabilities({bool refresh = false}) async =>
      value;
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

class FakePolicyErrorStartupViewModel extends StartupViewModel {
  FakePolicyErrorStartupViewModel(this.reason) {
    setError(reason.name);
  }

  final DownloadPolicyReason reason;

  @override
  DownloadPolicyReason? get downloadPolicyReason => reason;
}

void main() {
  setUp(() {
    registerTestHelpers();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.single.physicalSize = const Size(
      1200,
      1000,
    );
    binding.platformDispatcher.views.single.devicePixelRatio = 1;
  });

  tearDown(() async {
    await unregisterTestHelpers();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.single.resetPhysicalSize();
    binding.platformDispatcher.views.single.resetDevicePixelRatio();
  });

  Widget buildSubject(StartupViewModel viewModel, {Locale? locale}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StartupView(viewModel: viewModel, onViewModelReadyCallback: (_) {}),
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

  testWidgets('localizes policy denial errors at the startup UI boundary', (
    tester,
  ) async {
    final viewModel = FakePolicyErrorStartupViewModel(
      DownloadPolicyReason.connectivityUnknown,
    );

    await tester.pumpWidget(
      buildSubject(viewModel, locale: const Locale('es')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Las descargas están pausadas porque no se pudo determinar el tipo de '
        'conexión.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(DownloadPolicyReason.connectivityUnknown.name),
      findsNothing,
    );
  });

  testWidgets('renders token entry and copy repo link buttons on auth error', (
    tester,
  ) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedText = (methodCall.arguments as Map)['text'] as String?;
          }
          return null;
        });

    final modelService = getAndRegisterMockModelManagementService();
    final gatedModel =
        ModelInfo(
            id: InferenceModels.gemma3_270M.id,
            name: InferenceModels.gemma3_270M.name,
            url:
                'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/model.task',
            type: AppModelType.inference,
          )
          ..status = ModelStatus.error
          ..failureKind = ModelDownloadFailureKind.gatedAccess;

    final embeddingModel = ModelInfo(
      id: EmbeddingModels.gecko64.id,
      name: EmbeddingModels.gecko64.name,
      url: 'https://example.com/embedding',
      type: AppModelType.embedding,
    )..status = ModelStatus.downloaded;

    when(() => modelService.models).thenReturn([gatedModel, embeddingModel]);

    final viewModel = StartupViewModel(
      navigationService: MockNavigationService(),
      modelService: modelService,
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 2048,
          availableStorageMB: 2048,
          hasGpu: false,
          platform: 'android',
        ),
      ),
      recommendationService: FakeModelRecommendationService(),
    );

    await viewModel.runStartupLogic();
    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.byKey(const Key('copyRepoLinkButton')), findsOneWidget);
    expect(find.text('Enter Token'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copyRepoLinkButton')));
    await tester.pump();

    expect(
      copiedText,
      'https://huggingface.co/litert-community/Gemma3-1B-IT',
    );
  });

  testWidgets('does not offer a repo link for a non-gated auth error', (
    tester,
  ) async {
    final modelService = getAndRegisterMockModelManagementService();
    final authModel =
        ModelInfo(
            id: InferenceModels.gemma3_270M.id,
            name: InferenceModels.gemma3_270M.name,
            url:
                'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/model.task',
            type: AppModelType.inference,
          )
          ..status = ModelStatus.error
          ..failureKind = ModelDownloadFailureKind.authentication;
    final embeddingModel = ModelInfo(
      id: EmbeddingModels.gecko64.id,
      name: EmbeddingModels.gecko64.name,
      url: 'https://example.com/embedding',
      type: AppModelType.embedding,
    )..status = ModelStatus.downloaded;
    when(() => modelService.models).thenReturn([authModel, embeddingModel]);

    final viewModel = StartupViewModel(
      navigationService: MockNavigationService(),
      modelService: modelService,
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 2048,
          availableStorageMB: 2048,
          hasGpu: false,
          platform: 'android',
        ),
      ),
      recommendationService: FakeModelRecommendationService(),
    );

    await viewModel.runStartupLogic();
    await tester.pumpWidget(buildSubject(viewModel));

    expect(find.text('Enter Token'), findsOneWidget);
    expect(find.byKey(const Key('copyRepoLinkButton')), findsNothing);
  });
}
