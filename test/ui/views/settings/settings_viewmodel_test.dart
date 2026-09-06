import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/document_management_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/settings/settings_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../../helpers/test_helpers.dart';

class FakeDeviceCapabilityService extends DeviceCapabilityService {
  FakeDeviceCapabilityService(this.capabilities);

  final DeviceCapabilities capabilities;

  @override
  Future<DeviceCapabilities> getCapabilities({bool refresh = false}) async =>
      capabilities;
}

class ThrowingDeviceCapabilityService extends DeviceCapabilityService {
  @override
  Future<DeviceCapabilities> getCapabilities({bool refresh = false}) async {
    throw StateError('capability read failed');
  }
}

class MockDocumentManagementService extends Mock
    implements DocumentManagementService {}

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

  test(
    'handles expected model stream errors without uncaught errors',
    () async {
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
      )..setup();
      await Future<void>.delayed(Duration.zero);

      statusController.addError(StateError('expected download failure'));
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.hasModelStatusError, isTrue);
      viewModel.dispose();
    },
  );

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
    viewModel.onRerankTopKChanged(12);
    await viewModel.onRerankTopKChangeEnd(12);
    viewModel.onMaxDocumentSizeChanged(75);
    await viewModel.onMaxDocumentSizeChangeEnd(75);
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
    verify(() => ragSettings.setRerankTopK(12)).called(1);
    verify(() => ragSettings.setMaxDocumentSizeMB(75)).called(1);
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

  test('delegates token and personal-data cleanup actions', () async {
    var savedToken = '';
    var tokenCleared = false;
    var historyCleared = false;
    var crashLogsCleared = false;
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
      saveTokenAction: (token) async => savedToken = token,
      clearTokenAction: () async => tokenCleared = true,
      clearChatHistoryAction: () async => historyCleared = true,
      getCrashLogsAction: () async => ['[safe crash record]'],
      clearCrashLogsAction: () async => crashLogsCleared = true,
    );

    expect(await viewModel.saveToken('hf_test'), isTrue);
    await viewModel.clearToken();
    await viewModel.clearChatHistory();
    await viewModel.loadCrashLogs();
    await viewModel.clearCrashLogs();

    expect(savedToken, 'hf_test');
    expect(tokenCleared, isTrue);
    expect(historyCleared, isTrue);
    expect(crashLogsCleared, isTrue);
    expect(viewModel.crashLogs, isEmpty);
  });

  test('clearChatHistory returns a success result', () async {
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
      clearChatHistoryAction: () async {},
    );

    expect(await viewModel.clearChatHistory(), isTrue);
  });

  test('covers confirmed data controls and all displayed settings', () async {
    final dialogService = getAndRegisterMockDialogService();
    final documentService = MockDocumentManagementService();
    final document = Document(
      id: 'document-1',
      title: 'Document',
      filePath: '/tmp/document.txt',
      format: DocumentFormat.plainText,
      chunkCount: 1,
      totalCharacters: 10,
      contentHash: 'hash',
      ingestedAt: DateTime(2024),
      embeddingModelId: 'embedding-a',
    );
    when(
      () => dialogService.showConfirmationDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
        confirmationTitle: any(named: 'confirmationTitle'),
      ),
    ).thenAnswer((_) async => DialogResponse(confirmed: true));
    when(
      () => dialogService.showConfirmationDialog(
        title: any(named: 'title'),
        description: any(named: 'description'),
        confirmationTitle: any(named: 'confirmationTitle'),
        cancelTitle: any(named: 'cancelTitle'),
      ),
    ).thenAnswer((_) async => DialogResponse(confirmed: true));
    when(documentService.getAllDocuments).thenAnswer((_) async => [document]);
    when(() => modelService.deleteModel(any())).thenAnswer((_) async => true);
    when(() => ragSettings.rerankTopK).thenReturn(9);
    when(() => ragSettings.searchTopK).thenReturn(4);
    when(() => ragSettings.maxHistoryMessages).thenReturn(3);
    when(() => ragSettings.maxDocumentSizeMB).thenReturn(75);
    when(() => ragSettings.activeInferenceContextLimit).thenReturn(2048);

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
      dialogService: dialogService,
      documentService: documentService,
      getCrashLogsAction: () async => ['diagnostic'],
      clearCrashLogsAction: () async {},
      clearChatHistoryAction: () async {},
      saveTokenAction: (_) async {},
      clearTokenAction: () async {},
    );

    expect(viewModel.rerankTopKDisplay, 9);
    expect(viewModel.searchTopKDisplay, 4);
    expect(viewModel.maxHistoryMessagesDisplay, 3);
    expect(viewModel.maxDocumentSizeMB, 75);
    expect(viewModel.maxDocumentSizeDisplay, 75);
    expect(viewModel.maxTokensLimit, 2048);
    viewModel
      ..onRerankTopKChanged(12)
      ..onSearchTopKChanged(2)
      ..onMaxHistoryMessagesChanged(5)
      ..onMaxDocumentSizeChanged(80);
    await viewModel.onRerankTopKChangeEnd(12);
    await viewModel.onSearchTopKChangeEnd(2);
    await viewModel.onMaxHistoryMessagesChangeEnd(5);
    await viewModel.onMaxDocumentSizeChangeEnd(80);

    expect(await viewModel.deleteModel('inference-a'), isTrue);
    expect(await viewModel.clearChatHistory(), isTrue);
    await viewModel.loadCrashLogs();
    await viewModel.clearCrashLogs();
    await viewModel.enterToken();
    await viewModel.switchEmbeddingModel('embedding-b');
    await viewModel.exportCrashLogs();
  });

  test('surfaces recoverable action failures without throwing', () async {
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
      saveTokenAction: (_) async => throw StateError('save failed'),
      clearTokenAction: () async => throw StateError('clear failed'),
      clearChatHistoryAction: () async => throw StateError('history failed'),
      getCrashLogsAction: () async => throw StateError('load failed'),
      clearCrashLogsAction: () async => throw StateError('logs failed'),
    );
    when(() => modelService.downloadModel(any())).thenThrow(
      StateError('download failed'),
    );
    when(() => modelService.deleteModel(any())).thenThrow(
      StateError('delete failed'),
    );
    when(() => modelService.switchInferenceModel(any())).thenThrow(
      StateError('inference switch failed'),
    );
    when(() => modelService.switchEmbeddingModel(any())).thenThrow(
      StateError('embedding switch failed'),
    );

    await viewModel.downloadModel('inference-a');
    expect(await viewModel.deleteModel('inference-a'), isFalse);
    expect(await viewModel.saveToken('bad'), isFalse);
    await viewModel.clearToken();
    expect(await viewModel.clearChatHistory(), isFalse);
    await viewModel.loadCrashLogs();
    await viewModel.clearCrashLogs();
    await viewModel.switchInferenceModel('inference-a');
    await viewModel.switchEmbeddingModel('embedding-a');

    expect(viewModel.actionError, isNotNull);
    expect(viewModel.isLoadingCrashLogs, isFalse);
  });

  test(
    'does not notify after an async operation loses the view',
    () async {
      final completer = Completer<void>();
      when(
        () => ragSettings.setSemanticWeight(any()),
      ).thenAnswer((_) => completer.future);
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
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      final pending = viewModel.onSemanticWeightChangeEnd(0.4);
      viewModel.dispose();
      completer.complete();
      await pending;

      expect(notifications, 0);
    },
  );

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

  test(
    'records initialization, persistence, and model action failures',
    () async {
      when(modelService.initialize).thenThrow(StateError('initialize failed'));
      when(() => modelService.downloadModel(any())).thenThrow(
        StateError('download failed'),
      );
      when(() => modelService.switchInferenceModel(any())).thenThrow(
        StateError('inference switch failed'),
      );
      when(() => modelService.switchEmbeddingModel(any())).thenThrow(
        StateError('embedding switch failed'),
      );
      when(
        () => ragSettings.setQueryExpansionEnabled(value: any(named: 'value')),
      ).thenThrow(StateError('settings failed'));

      final viewModel = SettingsViewModel(
        modelService: modelService,
        ragSettings: ragSettings,
        navigationService: navigationService,
        deviceService: ThrowingDeviceCapabilityService(),
        saveTokenAction: (_) async => throw StateError('token save failed'),
        clearTokenAction: () async => throw StateError('token clear failed'),
        clearChatHistoryAction: () async => throw StateError('history failed'),
        getCrashLogsAction: () async => throw StateError('logs load failed'),
        clearCrashLogsAction: () async => throw StateError('logs clear failed'),
      );

      // The remaining calls are awaited individually, so a cascade would be
      // misleading here.
      // ignore: cascade_invocations
      viewModel.setup();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await viewModel.downloadModel('inference-a');
      await viewModel.switchInferenceModel('inference-a');
      await viewModel.switchEmbeddingModel('embedding-a');
      await viewModel.toggleQueryExpansion(true);
      expect(await viewModel.saveToken('bad'), isFalse);
      await viewModel.clearToken();
      expect(await viewModel.clearChatHistory(), isFalse);
      await viewModel.loadCrashLogs();
      await viewModel.clearCrashLogs();

      expect(viewModel.actionError, isNotNull);
      expect(viewModel.hasModelStatusError, isTrue);
      expect(viewModel.isLoadingCrashLogs, isFalse);
      viewModel.dispose();
    },
  );

  test('checks reindex impact before switching the embedding model', () async {
    final dialogService = getAndRegisterMockDialogService();
    final documentService = MockDocumentManagementService();
    when(documentService.getAllDocuments).thenThrow(
      StateError('status read failed'),
    );

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
      dialogService: dialogService,
      documentService: documentService,
    );

    await viewModel.switchEmbeddingModel('embedding-b');
    expect(viewModel.actionError, isNotNull);
    verifyNever(() => modelService.switchEmbeddingModel('embedding-b'));
  });

  test(
    'does not switch embedding model when reindex confirmation is declined',
    () async {
      final dialogService = getAndRegisterMockDialogService();
      final documentService = MockDocumentManagementService();
      final document = Document(
        id: 'document-1',
        title: 'Document',
        filePath: '/tmp/document.txt',
        format: DocumentFormat.plainText,
        chunkCount: 1,
        totalCharacters: 10,
        contentHash: 'hash',
        ingestedAt: DateTime(2024),
        embeddingModelId: 'embedding-a',
        status: IngestionStatus.complete,
      );
      when(documentService.getAllDocuments).thenAnswer((_) async => [document]);
      when(
        () => dialogService.showConfirmationDialog(
          title: any(named: 'title'),
          description: any(named: 'description'),
          confirmationTitle: any(named: 'confirmationTitle'),
          cancelTitle: any(named: 'cancelTitle'),
        ),
      ).thenAnswer((_) async => DialogResponse());

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
        dialogService: dialogService,
        documentService: documentService,
      );

      await viewModel.switchEmbeddingModel('embedding-b');

      verify(
        () => dialogService.showConfirmationDialog(
          title: any(named: 'title'),
          description: any(named: 'description'),
          confirmationTitle: any(named: 'confirmationTitle'),
          cancelTitle: any(named: 'cancelTitle'),
        ),
      ).called(1);
      verifyNever(() => modelService.switchEmbeddingModel('embedding-b'));
    },
  );
}
