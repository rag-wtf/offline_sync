import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing RAG quality settings and user preferences
class RagSettingsService {
  static const _keyQueryExpansion = 'rag_query_expansion_enabled';
  static const _keyReranking = 'rag_reranking_enabled';
  static const _keyChunkOverlap = 'rag_chunk_overlap_percent';
  static const _keySemanticWeight = 'rag_semantic_weight';
  static const _keyRerankTopK = 'rag_rerank_top_k';

  // Feature toggles - defaults to OFF for performance
  bool _queryExpansionEnabled = false;
  bool _rerankingEnabled = false;

  // Parameters
  double _chunkOverlapPercent = 0.15; // 15% overlap
  double _semanticWeight = 0.7; // 70% semantic, 30% keyword
  int _rerankTopK = 10; // Rerank top 10 candidates

  bool get queryExpansionEnabled => _queryExpansionEnabled;
  bool get rerankingEnabled => _rerankingEnabled;
  double get chunkOverlapPercent => _chunkOverlapPercent;
  double get semanticWeight => _semanticWeight;
  int get rerankTopK => _rerankTopK;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _queryExpansionEnabled = prefs.getBool(_keyQueryExpansion) ?? false;
    _rerankingEnabled = prefs.getBool(_keyReranking) ?? false;
    _chunkOverlapPercent = prefs.getDouble(_keyChunkOverlap) ?? 0.15;
    _semanticWeight = prefs.getDouble(_keySemanticWeight) ?? 0.7;
    _rerankTopK = prefs.getInt(_keyRerankTopK) ?? 10;
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
}
