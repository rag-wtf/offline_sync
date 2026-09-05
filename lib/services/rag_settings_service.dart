import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/services/inference_model_provider.dart';
import 'package:offline_sync/services/model_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing RAG quality settings and user preferences
class RagSettingsService {
  static const _keyQueryExpansion = 'rag_query_expansion_enabled';
  static const _keyReranking = 'rag_reranking_enabled';
  static const _keyChunkOverlap = 'rag_chunk_overlap_percent';
  static const _keySemanticWeight = 'rag_semantic_weight';
  static const _keyRerankTopK = 'rag_rerank_top_k';
  static const _keySearchTopK = 'rag_search_top_k';
  static const _keyMaxHistoryMessages = 'rag_max_history_messages';
  static const _keyMaxTokens = 'rag_max_tokens';
  static const _keyActiveInferenceModel = 'active_inference_model_id';
  static const _keyActiveEmbeddingModel = 'active_embedding_model_id';

  // Feature toggles - defaults to OFF for performance
  bool _queryExpansionEnabled = false;
  bool _rerankingEnabled = false;

  // Parameters
  double _chunkOverlapPercent = 0.15; // 15% overlap
  double _semanticWeight = 0.7; // 70% semantic, 30% keyword
  int _rerankTopK = 10; // Rerank top 10 candidates
  int _searchTopK = 2; // Number of chunks to retrieve (conservative)
  int _maxHistoryMessages = 2; // Max conversation history (conservative)
  int? _maxTokens; // User override for max tokens (null = use model default)
  String? _activeInferenceModelId;
  String? _activeEmbeddingModelId;

  bool get queryExpansionEnabled => _queryExpansionEnabled;
  bool get rerankingEnabled => _rerankingEnabled;
  double get chunkOverlapPercent => _chunkOverlapPercent;
  double get semanticWeight => _semanticWeight;
  int get rerankTopK => _rerankTopK;
  int get searchTopK => _searchTopK;
  int get maxHistoryMessages => _maxHistoryMessages;
  int? get maxTokens => _maxTokens == null
      ? null
      : _clampMaxTokens(_maxTokens!); // null means use model default
  int get activeInferenceContextLimit =>
      ModelConfig.activeInferenceContextLimit(_activeInferenceModelId);
  String? get activeInferenceModelId => _activeInferenceModelId;
  String? get activeEmbeddingModelId => _activeEmbeddingModelId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _queryExpansionEnabled = prefs.getBool(_keyQueryExpansion) ?? false;
    _rerankingEnabled = prefs.getBool(_keyReranking) ?? false;
    _chunkOverlapPercent = (prefs.getDouble(_keyChunkOverlap) ?? 0.15).clamp(
      0.0,
      0.3,
    );
    _semanticWeight = (prefs.getDouble(_keySemanticWeight) ?? 0.7).clamp(
      0.0,
      1.0,
    );
    _rerankTopK = (prefs.getInt(_keyRerankTopK) ?? 10).clamp(5, 20);
    _searchTopK = (prefs.getInt(_keySearchTopK) ?? 2).clamp(1, 5);
    _maxHistoryMessages = (prefs.getInt(_keyMaxHistoryMessages) ?? 2).clamp(
      0,
      5,
    );
    final savedInferenceModelId = prefs.getString(_keyActiveInferenceModel);
    _activeInferenceModelId =
        _isModelIdValid(
          savedInferenceModelId,
          AppModelType.inference,
        )
        ? savedInferenceModelId
        : null;
    if (savedInferenceModelId != null && _activeInferenceModelId == null) {
      await prefs.remove(_keyActiveInferenceModel);
    }

    final savedEmbeddingModelId = prefs.getString(_keyActiveEmbeddingModel);
    _activeEmbeddingModelId =
        _isModelIdValid(
          savedEmbeddingModelId,
          AppModelType.embedding,
        )
        ? savedEmbeddingModelId
        : null;
    if (savedEmbeddingModelId != null && _activeEmbeddingModelId == null) {
      await prefs.remove(_keyActiveEmbeddingModel);
    }
    final rawMaxTokens = prefs.getInt(_keyMaxTokens);
    _maxTokens = rawMaxTokens == null ? null : _clampMaxTokens(rawMaxTokens);
    if (_maxTokens != null && _maxTokens != rawMaxTokens) {
      await prefs.setInt(_keyMaxTokens, _maxTokens!);
    }

    // Document Management Settings (Issue #17 fix)
    _maxDocumentSizeMB = (prefs.getInt(_keyMaxDocumentSizeMB) ?? 10).clamp(
      1,
      50,
    );
    _contextualRetrievalEnabled =
        prefs.getBool(_keyContextualRetrieval) ?? false;
  }

  Future<void> setQueryExpansionEnabled({required bool value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyQueryExpansion, value);
    _queryExpansionEnabled = value;
  }

  Future<void> setRerankingEnabled({required bool value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReranking, value);
    _rerankingEnabled = value;
  }

  Future<void> setChunkOverlapPercent(double value) async {
    final normalizedValue = value.clamp(0.0, 0.3); // Max 30% overlap
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyChunkOverlap, normalizedValue);
    _chunkOverlapPercent = normalizedValue;
  }

  Future<void> setSemanticWeight(double value) async {
    final normalizedValue = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySemanticWeight, normalizedValue);
    _semanticWeight = normalizedValue;
  }

  Future<void> setRerankTopK(int value) async {
    final normalizedValue = value.clamp(5, 20); // Between 5 and 20
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRerankTopK, normalizedValue);
    _rerankTopK = normalizedValue;
  }

  Future<void> setSearchTopK(int value) async {
    final normalizedValue = value.clamp(1, 5); // Between 1 and 5
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySearchTopK, normalizedValue);
    _searchTopK = normalizedValue;
  }

  Future<void> setMaxHistoryMessages(int value) async {
    final normalizedValue = value.clamp(0, 5); // Between 0 and 5
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxHistoryMessages, normalizedValue);
    _maxHistoryMessages = normalizedValue;
  }

  Future<void> setMaxTokens(int? value) async {
    if (value == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyMaxTokens); // Remove to use model default
      _maxTokens = null;
    } else {
      final normalizedValue = _clampMaxTokens(value);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyMaxTokens, normalizedValue);
      _maxTokens = normalizedValue;
    }
    if (locator.isRegistered<InferenceModelProvider>()) {
      locator<InferenceModelProvider>().clearCache();
    }
  }

  Future<void> setActiveInferenceModelId(String id) async {
    _validateModelId(id, AppModelType.inference);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveInferenceModel, id);
    _activeInferenceModelId = id;
    if (_maxTokens != null) {
      _maxTokens = _clampMaxTokens(_maxTokens!);
      await prefs.setInt(_keyMaxTokens, _maxTokens!);
    }
    if (locator.isRegistered<InferenceModelProvider>()) {
      locator<InferenceModelProvider>().clearCache();
    }
  }

  Future<void> setActiveEmbeddingModelId(String id) async {
    _validateModelId(id, AppModelType.embedding);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveEmbeddingModel, id);
    _activeEmbeddingModelId = id;
  }

  Future<void> clearActiveInferenceModelId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActiveInferenceModel);
    _activeInferenceModelId = null;
  }

  Future<void> clearActiveEmbeddingModelId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActiveEmbeddingModel);
    _activeEmbeddingModelId = null;
  }

  // Document Management Settings
  static const _keyMaxDocumentSizeMB = 'rag_max_doc_size_mb';
  static const _keyContextualRetrieval = 'rag_contextual_retrieval_enabled';

  int _maxDocumentSizeMB = 10; // Default 10MB
  bool _contextualRetrievalEnabled = false;

  int get maxDocumentSizeMB => _maxDocumentSizeMB;
  bool get contextualRetrievalEnabled => _contextualRetrievalEnabled;

  // Dynamic token limit: Double the base limit if CR is enabled
  // Base is usually 4096 (High tier), so this allows ~8192 tokens (~32k chars)
  // when contextual retrieval is active, assuming the model supports it
  // (e.g. Premium).
  bool get doubleMaxTokens => _contextualRetrievalEnabled;

  Future<void> setMaxDocumentSizeMB(int value) async {
    final normalizedValue = value.clamp(1, 50); // 1MB to 50MB
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxDocumentSizeMB, normalizedValue);
    _maxDocumentSizeMB = normalizedValue;
  }

  Future<void> setContextualRetrievalEnabled({required bool value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyContextualRetrieval, value);
    _contextualRetrievalEnabled = value;
  }

  int _clampMaxTokens(int value) {
    final upperBound = activeInferenceContextLimit;
    return value.clamp(512, upperBound);
  }

  bool _isModelIdValid(String? id, AppModelType type) {
    if (id == null) return false;
    return ModelConfig.allModels.any(
      (model) => model.id == id && model.type == type,
    );
  }

  void _validateModelId(String id, AppModelType type) {
    if (!_isModelIdValid(id, type)) {
      throw ArgumentError.value(id, 'id', 'Unknown $type model id');
    }
  }
}
