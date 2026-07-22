import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/settings/settings_view.dart';
import 'package:offline_sync/ui/views/settings/settings_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

class FakeDeviceCapabilityService extends DeviceCapabilityService {
  FakeDeviceCapabilityService(this.capabilities);

  final DeviceCapabilities capabilities;

  @override
  Future<DeviceCapabilities> getCapabilities() async => capabilities;
}

void main() {
  late MockModelManagementService modelService;
  late MockRagSettingsService ragSettings;
  late MockNavigationService navigationService;
  late List<ModelInfo> models;

  setUp(() {
    modelService = getAndRegisterMockModelManagementService();
    ragSettings = getAndRegisterMockRagSettingsService();
    navigationService = getAndRegisterMockNavigationService();

    models = [
      ModelInfo(
        id: 'inference-a',
        name: 'Inference A',
        url: 'https://example.com/a',
        type: AppModelType.inference,
      )..status = ModelStatus.downloaded,
      ModelInfo(
        id: 'inference-b',
        name: 'Inference B',
        url: 'https://example.com/b',
        type: AppModelType.inference,
      )..status = ModelStatus.downloaded,
      ModelInfo(
        id: 'embedding-a',
        name: 'Embedding A',
        url: 'https://example.com/c',
        type: AppModelType.embedding,
      )..status = ModelStatus.downloaded,
      ModelInfo(
        id: 'embedding-b',
        name: 'Embedding B',
        url: 'https://example.com/d',
        type: AppModelType.embedding,
      )..status = ModelStatus.notDownloaded,
    ];

    when(() => modelService.models).thenReturn(models);
    when(() => modelService.downloadedInferenceModels).thenReturn(
      models.where((model) => model.type == AppModelType.inference).toList(),
    );
    when(() => modelService.downloadedEmbeddingModels).thenReturn(
      models
          .where(
            (model) =>
                model.type == AppModelType.embedding &&
                model.status == ModelStatus.downloaded,
          )
          .toList(),
    );
    when(() => modelService.activeInferenceModel).thenReturn(models.first);
    when(() => modelService.activeEmbeddingModel).thenReturn(models[2]);
    when(
      () => modelService.modelStatusStream,
    ).thenAnswer((_) => const Stream.empty());
    when(modelService.initialize).thenAnswer((_) async {});
    when(() => modelService.downloadModel(any())).thenAnswer((_) async {});
    when(
      () => modelService.switchInferenceModel(any()),
    ).thenAnswer((_) async {});
    when(
      () => modelService.switchEmbeddingModel(any()),
    ).thenAnswer((_) async {});
    when(() => ragSettings.maxTokens).thenReturn(2048);
    when(() => ragSettings.queryExpansionEnabled).thenReturn(false);
    when(() => ragSettings.rerankingEnabled).thenReturn(true);
    when(() => ragSettings.contextualRetrievalEnabled).thenReturn(true);
    when(() => ragSettings.chunkOverlapPercent).thenReturn(0.2);
    when(() => ragSettings.semanticWeight).thenReturn(0.4);
    when(() => ragSettings.searchTopK).thenReturn(4);
    when(() => ragSettings.maxHistoryMessages).thenReturn(3);
    when(
      () => ragSettings.setQueryExpansionEnabled(value: any(named: 'value')),
    ).thenAnswer((_) async {});
    when(
      () => ragSettings.setRerankingEnabled(value: any(named: 'value')),
    ).thenAnswer((_) async {});
    when(
      () =>
          ragSettings.setContextualRetrievalEnabled(value: any(named: 'value')),
    ).thenAnswer((_) async {});
    when(
      () => navigationService.navigateTo<dynamic>(
        any(),
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(unregisterTestHelpers);

  Future<void> pumpView(
    WidgetTester tester, {
    required SettingsViewModel viewModel,
    void Function(SettingsViewModel viewModel)? callback,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          viewModel: viewModel,
          onViewModelReadyCallback: callback,
        ),
      ),
    );
  }

  testWidgets('renders settings sections and delegates interactions', (
    tester,
  ) async {
    final viewModel = SettingsViewModel(
      modelService: modelService,
      ragSettings: ragSettings,
      navigationService: navigationService,
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 8192,
          availableStorageMB: 4096,
          hasGpu: true,
          platform: 'linux',
        ),
      ),
    );

    await pumpView(tester, viewModel: viewModel, callback: (vm) => vm.setup());
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('AI Model Management'), findsOneWidget);
    expect(find.text('Active Inference Model'), findsOneWidget);
    expect(find.text('Available Models'), findsOneWidget);
    await tester.tap(find.text('Inference B').first);
    await tester.pump();
    verify(() => modelService.switchInferenceModel('inference-b')).called(1);

    await tester.scrollUntilVisible(find.text('Query Expansion'), 300);
    await tester.tap(find.text('Query Expansion'));
    await tester.pump();
    verify(() => ragSettings.setQueryExpansionEnabled(value: true)).called(1);

    await tester.scrollUntilVisible(
      find.text('Manage Knowledge Base'),
      300,
    );
    expect(find.text('Manage Knowledge Base'), findsOneWidget);
    await tester.tap(find.text('Manage Knowledge Base'));
    await tester.pump();
    verify(
      () => navigationService.navigateTo<dynamic>(
        any(),
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).called(1);

    await tester.scrollUntilVisible(find.text('Device Information'), 300);
    expect(find.text('Device Information'), findsOneWidget);
    expect(find.text('LINUX'), findsOneWidget);
  });

  testWidgets(
    'renders active embedding models and delegates embedding switch',
    (
      tester,
    ) async {
      models[3].status = ModelStatus.downloaded;
      when(() => modelService.downloadedEmbeddingModels).thenReturn(
        models.where((model) => model.type == AppModelType.embedding).toList(),
      );

      final viewModel = SettingsViewModel(
        modelService: modelService,
        ragSettings: ragSettings,
        navigationService: navigationService,
        deviceService: FakeDeviceCapabilityService(
          const DeviceCapabilities(
            totalRamMB: 8192,
            availableStorageMB: 4096,
            hasGpu: true,
            platform: 'linux',
          ),
        ),
      );

      await pumpView(
        tester,
        viewModel: viewModel,
        callback: (vm) => vm.setup(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active Embedding Model'), findsOneWidget);
      expect(find.text('Embedding A'), findsWidgets);
      expect(find.text('Embedding B'), findsWidgets);
      expect(find.text('ACTIVE'), findsAtLeastNWidgets(2));

      await tester.tap(find.text('Embedding B').first);
      await tester.pump();

      verify(() => modelService.switchEmbeddingModel('embedding-b')).called(1);
    },
  );

  testWidgets('renders model download states and device values in megabytes', (
    tester,
  ) async {
    models[1]
      ..status = ModelStatus.downloading
      ..progress = 0.5;
    models[2].status = ModelStatus.error;

    final viewModel = SettingsViewModel(
      modelService: modelService,
      ragSettings: ragSettings,
      navigationService: navigationService,
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 512,
          availableStorageMB: 768,
          hasGpu: false,
          platform: 'android',
        ),
      ),
    );

    await pumpView(tester, viewModel: viewModel);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.downloading_rounded), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    await tester.scrollUntilVisible(find.byIcon(Icons.refresh_rounded), 300);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    verify(() => modelService.downloadModel('embedding-a')).called(1);

    await tester.scrollUntilVisible(find.byIcon(Icons.download_rounded), 300);
    await tester.tap(find.byIcon(Icons.download_rounded));
    await tester.pump();
    verify(() => modelService.downloadModel('embedding-b')).called(1);

    await tester.scrollUntilVisible(find.text('Device Information'), 300);
    expect(find.text('512 MB'), findsOneWidget);
    expect(find.text('768 MB'), findsOneWidget);
    expect(find.text('Not Available'), findsOneWidget);
  });

  testWidgets(
    'omits optional sections when models and capabilities are absent',
    (
      tester,
    ) async {
      when(
        () => modelService.downloadedInferenceModels,
      ).thenReturn([models.first]);
      when(
        () => modelService.downloadedEmbeddingModels,
      ).thenReturn([models[2]]);

      final viewModel = SettingsViewModel(
        modelService: modelService,
        ragSettings: ragSettings,
        navigationService: navigationService,
        deviceService: FakeDeviceCapabilityService(
          const DeviceCapabilities(
            totalRamMB: 4096,
            availableStorageMB: 2048,
            hasGpu: false,
            platform: 'android',
          ),
        ),
      );

      await pumpView(tester, viewModel: viewModel);

      expect(find.text('Active Inference Model'), findsNothing);
      expect(find.text('Active Embedding Model'), findsNothing);
      expect(find.text('Device Information'), findsNothing);
    },
  );
}
