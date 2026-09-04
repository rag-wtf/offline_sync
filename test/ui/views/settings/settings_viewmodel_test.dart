import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/settings/settings_viewmodel.dart';

import '../../../helpers/test_helpers.dart';

class FakeDeviceCapabilityService extends DeviceCapabilityService {
  FakeDeviceCapabilityService(this.capabilities);

  final DeviceCapabilities capabilities;

  @override
  Future<DeviceCapabilities> getCapabilities({bool refresh = false}) async =>
      capabilities;
}

void main() {
  late MockModelManagementService modelService;
  late MockRagSettingsService ragSettings;
  late MockNavigationService navigationService;
  late StreamController<List<ModelInfo>> statusController;
  late List<ModelInfo> models;

  setUp(() {
    modelService = getAndRegisterMockModelManagementService();
    ragSettings = getAndRegisterMockRagSettingsService();
    navigationService = getAndRegisterMockNavigationService();
    statusController = StreamController<List<ModelInfo>>.broadcast();

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
        url: 'https://example.com/e1',
        type: AppModelType.embedding,
      )..status = ModelStatus.downloaded,
      ModelInfo(
        id: 'embedding-b',
        name: 'Embedding B',
        url: 'https://example.com/e2',
        type: AppModelType.embedding,
      )..status = ModelStatus.downloaded,
    ];

    when(() => modelService.models).thenReturn(models);
    when(() => modelService.downloadedInferenceModels).thenReturn(
      models.where((m) => m.type == AppModelType.inference).toList(),
    );
    when(() => modelService.downloadedEmbeddingModels).thenReturn(
      models.where((m) => m.type == AppModelType.embedding).toList(),
    );
    when(() => modelService.activeInferenceModel).thenReturn(models.first);
    when(() => modelService.activeEmbeddingModel).thenReturn(models[2]);
    when(
      () => modelService.modelStatusStream,
    ).thenAnswer((_) => statusController.stream);
    when(modelService.initialize).thenAnswer((_) async {});
    when(() => modelService.downloadModel(any())).thenAnswer((_) async {});
    when(
      () => modelService.switchInferenceModel(any()),
    ).thenAnswer((_) async {});
    when(
      () => modelService.switchEmbeddingModel(any()),
    ).thenAnswer((_) async {});
    when(() => ragSettings.maxTokens).thenReturn(null);
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
      () => ragSettings.setChunkOverlapPercent(any()),
    ).thenAnswer((_) async {});
    when(() => ragSettings.setSemanticWeight(any())).thenAnswer((_) async {});
    when(() => ragSettings.setSearchTopK(any())).thenAnswer((_) async {});
    when(
      () => ragSettings.setMaxHistoryMessages(any()),
    ).thenAnswer((_) async {});
    when(() => ragSettings.setMaxTokens(any())).thenAnswer((_) async {});
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

  tearDown(() async {
    await statusController.close();
    await unregisterTestHelpers();
  });

  test('setup initializes model service and loads capabilities', () async {
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
    )..setup();
    await Future<void>.delayed(Duration.zero);

    verify(modelService.initialize).called(1);
    expect(viewModel.capabilities?.platform, 'linux');
    expect(viewModel.models, models);
    expect(viewModel.downloadedInferenceModels, hasLength(2));
    expect(viewModel.downloadedEmbeddingModels, hasLength(2));
  });

  test('setup listens for model status updates'
      ' and notifies listeners', () async {
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
    var notifications = 0;
    viewModel
      ..addListener(() => notifications++)
      ..setup();
    await Future<void>.delayed(Duration.zero);
    statusController.add(models);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, greaterThanOrEqualTo(2));
  });

  test('toggle and slider handlers persist new values', () async {
    final viewModel =
        SettingsViewModel(
            modelService: modelService,
            ragSettings: ragSettings,
            navigationService: navigationService,
            deviceService: FakeDeviceCapabilityService(
              const DeviceCapabilities(
                totalRamMB: 2048,
                availableStorageMB: 2048,
                hasGpu: false,
                platform: 'android',
              ),
            ),
          )
          ..onChunkOverlapChanged(22)
          ..onSemanticWeightChanged(0.4)
          ..onSearchTopKChanged(4)
          ..onMaxHistoryMessagesChanged(3)
          ..onMaxTokensChanged(2048);

    expect(viewModel.chunkOverlapDisplay, 22);
    expect(viewModel.semanticWeightDisplay, 0.4);
    expect(viewModel.searchTopKDisplay, 4);
    expect(viewModel.maxHistoryMessagesDisplay, 3);
    expect(viewModel.maxTokensDisplay, 2048);
    expect(viewModel.isMaxTokensCustomDisplay, isTrue);

    await viewModel.toggleQueryExpansion(true);
    await viewModel.toggleReranking(true);
    await viewModel.toggleContextualRetrieval(true);
    await viewModel.onChunkOverlapChangeEnd(22);
    await viewModel.onSemanticWeightChangeEnd(0.4);
    await viewModel.onSearchTopKChangeEnd(4);
    await viewModel.onMaxHistoryMessagesChangeEnd(3);
    await viewModel.onMaxTokensChangeEnd(2048);
    await viewModel.onMaxTokensChangeEnd(
      viewModel.modelDefaultMaxTokens.toDouble(),
    );

    verify(() => ragSettings.setQueryExpansionEnabled(value: true)).called(1);
    verify(() => ragSettings.setRerankingEnabled(value: true)).called(1);
    verify(
      () => ragSettings.setContextualRetrievalEnabled(value: true),
    ).called(1);
    verify(() => ragSettings.setChunkOverlapPercent(0.22)).called(1);
    verify(() => ragSettings.setSemanticWeight(0.4)).called(1);
    verify(() => ragSettings.setSearchTopK(4)).called(1);
    verify(() => ragSettings.setMaxHistoryMessages(3)).called(1);
    verify(() => ragSettings.setMaxTokens(2048)).called(1);
    verify(() => ragSettings.setMaxTokens(null)).called(1);
  });

  test('uses model defaults when max tokens have not been overridden', () {
    final viewModel = SettingsViewModel(
      modelService: modelService,
      ragSettings: ragSettings,
      navigationService: navigationService,
      deviceService: FakeDeviceCapabilityService(
        const DeviceCapabilities(
          totalRamMB: 2048,
          availableStorageMB: 2048,
          hasGpu: false,
          platform: 'android',
        ),
      ),
    );

    expect(viewModel.maxTokens, viewModel.modelDefaultMaxTokens);
    expect(viewModel.isMaxTokensCustom, isFalse);

    viewModel.onMaxTokensChanged(viewModel.modelDefaultMaxTokens.toDouble());

    expect(viewModel.isMaxTokensCustomDisplay, isFalse);
  });

  test('model actions and navigation delegate to services', () async {
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

    await viewModel.downloadModel('inference-a');
    await viewModel.switchInferenceModel('inference-b');
    await viewModel.switchEmbeddingModel('embedding-b');
    await viewModel.navigateToDocumentLibrary();

    verify(() => modelService.downloadModel('inference-a')).called(1);
    verify(() => modelService.switchInferenceModel('inference-b')).called(1);
    verify(() => modelService.switchEmbeddingModel('embedding-b')).called(1);
    verify(
      () => navigationService.navigateTo<dynamic>(
        Routes.documentLibraryView,
        arguments: any<dynamic>(named: 'arguments'),
        id: any(named: 'id'),
        preventDuplicates: any(named: 'preventDuplicates'),
        parameters: any(named: 'parameters'),
        transition: any(named: 'transition'),
      ),
    ).called(1);
  });

  test('reads default dependencies from locator and preserves'
      ' pending values during stale async updates', () async {
    final completer = Completer<void>();
    when(
      () => ragSettings.setChunkOverlapPercent(any()),
    ).thenAnswer((_) => completer.future);
    when(() => ragSettings.maxTokens).thenReturn(1234);

    final viewModel = SettingsViewModel();

    expect(viewModel.maxTokens, 1234);
    expect(viewModel.modelDefaultMaxTokens, greaterThan(0));
    expect(viewModel.queryExpansionEnabled, isFalse);
    expect(viewModel.rerankingEnabled, isFalse);
    expect(viewModel.contextualRetrievalEnabled, isFalse);
    expect(viewModel.activeInferenceModel?.id, models.first.id);
    expect(viewModel.activeEmbeddingModel?.id, models[2].id);
    expect(viewModel.downloadedInferenceModels, hasLength(2));
    expect(viewModel.downloadedEmbeddingModels, hasLength(2));

    viewModel.onChunkOverlapChanged(10);
    final pendingSave = viewModel.onChunkOverlapChangeEnd(10);
    viewModel.onChunkOverlapChanged(25);
    completer.complete();
    await pendingSave;

    expect(viewModel.chunkOverlapDisplay, 25);

    viewModel.dispose();
  });
}
