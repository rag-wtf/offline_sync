import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RagSettingsService -', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trips every persisted getter and setter', () async {
      final service = RagSettingsService();
      await service.initialize();

      await service.setQueryExpansionEnabled(value: true);
      await service.setRerankingEnabled(value: true);
      await service.setChunkOverlapPercent(0.25);
      await service.setSemanticWeight(0.35);
      await service.setRerankTopK(12);
      await service.setSearchTopK(4);
      await service.setMaxHistoryMessages(3);
      await service.setMaxTokens(4096);
      await service.setActiveInferenceModelId('gemma-inference');
      await service.setActiveEmbeddingModelId('gemma-embedding');
      await service.setMaxDocumentSizeMB(24);
      await service.setContextualRetrievalEnabled(value: true);

      final reloaded = RagSettingsService();
      await reloaded.initialize();

      expect(reloaded.queryExpansionEnabled, isTrue);
      expect(reloaded.rerankingEnabled, isTrue);
      expect(reloaded.chunkOverlapPercent, closeTo(0.25, 0.000001));
      expect(reloaded.semanticWeight, closeTo(0.35, 0.000001));
      expect(reloaded.rerankTopK, 12);
      expect(reloaded.searchTopK, 4);
      expect(reloaded.maxHistoryMessages, 3);
      expect(reloaded.maxTokens, 4096);
      expect(reloaded.activeInferenceModelId, 'gemma-inference');
      expect(reloaded.activeEmbeddingModelId, 'gemma-embedding');
      expect(reloaded.maxDocumentSizeMB, 24);
      expect(reloaded.contextualRetrievalEnabled, isTrue);
      expect(reloaded.doubleMaxTokens, isTrue);
    });

    test('clears nullable maxTokens override when set back to null', () async {
      final service = RagSettingsService();
      await service.initialize();

      await service.setMaxTokens(2048);
      await service.setMaxTokens(null);

      final reloaded = RagSettingsService();
      await reloaded.initialize();

      expect(reloaded.maxTokens, isNull);
      expect(reloaded.doubleMaxTokens, isFalse);
    });
  });
}
