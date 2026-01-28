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
  int? get maxTokens => _maxTokens; // null means use model default
  String? get activeInferenceModelId => _activeInferenceModelId;
  String? get activeEmbeddingModelId => _activeEmbeddingModelId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _queryExpansionEnabled = prefs.getBool(_keyQueryExpansion) ?? false;
    _rerankingEnabled = prefs.getBool(_keyReranking) ?? false;
    _chunkOverlapPercent = prefs.getDouble(_keyChunkOverlap) ?? 0.15;
    _semanticWeight = prefs.getDouble(_keySemanticWeight) ?? 0.7;
    _rerankTopK = prefs.getInt(_keyRerankTopK) ?? 10;
    _searchTopK = prefs.getInt(_keySearchTopK) ?? 2;
    _maxHistoryMessages = prefs.getInt(_keyMaxHistoryMessages) ?? 2;
    _maxTokens = prefs.getInt(_keyMaxTokens); // null if not set
    _activeInferenceModelId = prefs.getString(_keyActiveInferenceModel);
    _activeEmbeddingModelId = prefs.getString(_keyActiveEmbeddingModel);

    // Document Management Settings (Issue #17 fix)
    _maxDocumentSizeMB = prefs.getInt(_keyMaxDocumentSizeMB) ?? 10;
    _contextualRetrievalEnabled =
        prefs.getBool(_keyContextualRetrieval) ?? false;
  }

  Future<void> setQueryExpansionEnabled({required bool value}) async {
    _queryExpansionEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyQueryExpansion, value);
  }

  Future<void> setRerankingEnabled({required bool value}) async {
    _rerankingEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReranking, value);
  }

  Future<void> setChunkOverlapPercent(double value) async {
    _chunkOverlapPercent = value.clamp(0.0, 0.3); // Max 30% overlap
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyChunkOverlap, _chunkOverlapPercent);
  }

  Future<void> setSemanticWeight(double value) async {
    _semanticWeight = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySemanticWeight, _semanticWeight);
  }

  Future<void> setRerankTopK(int value) async {
    _rerankTopK = value.clamp(5, 20); // Between 5 and 20
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRerankTopK, _rerankTopK);
  }

  Future<void> setSearchTopK(int value) async {
    _searchTopK = value.clamp(1, 5); // Between 1 and 5
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySearchTopK, _searchTopK);
  }

  Future<void> setMaxHistoryMessages(int value) async {
    _maxHistoryMessages = value.clamp(0, 5); // Between 0 and 5
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxHistoryMessages, _maxHistoryMessages);
  }

  Future<void> setMaxTokens(int? value) async {
    if (value == null) {
      _maxTokens = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyMaxTokens); // Remove to use model default
    } else {
      _maxTokens = value.clamp(512, 8192); // Between 512 and 8192
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyMaxTokens, _maxTokens!);
    }
  }

  Future<void> setActiveInferenceModelId(String id) async {
    _activeInferenceModelId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveInferenceModel, id);
  }

  Future<void> setActiveEmbeddingModelId(String id) async {
    _activeEmbeddingModelId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveEmbeddingModel, id);
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
    _maxDocumentSizeMB = value.clamp(1, 50); // 1MB to 50MB
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxDocumentSizeMB, _maxDocumentSizeMB);
  }

  Future<void> setContextualRetrievalEnabled({required bool value}) async {
    _contextualRetrievalEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyContextualRetrieval, value);
  }
}
