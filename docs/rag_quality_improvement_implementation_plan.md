# RAG Quality Improvement Implementation Plan

Comprehensive enhancements to the existing RAG pipeline to improve retrieval accuracy, relevance, and response quality.

## Current State Analysis

The codebase already has:
- **Hybrid Search**: FTS5/BM25 + vector similarity with RRF merging ([vector_store.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/vector_store.dart))
- **Chunking**: Line-based chunking with 500 char limit ([rag_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_service.dart#L311-358))
- **Streaming RAG**: Token-by-token response streaming
- **Settings View**: Currently only manages AI models, no RAG settings

## User Review Required

> [!IMPORTANT]
> **Reranking Performance Trade-off**: LLM-based reranking adds latency (1-3 seconds per query). On low-end devices, this may significantly impact user experience. The setting will default to OFF.

> [!WARNING]
> **Query Expansion on Edge**: Using the on-device LLM for query expansion adds overhead. Consider if this is suitable for your use case, or if simple synonym expansion would suffice.

---

## Proposed Changes

### New Services Layer

#### [NEW] [rag_settings_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_settings_service.dart)

Manages user preferences for RAG quality features:

```dart
class RagSettingsService {
  // Feature toggles
  bool queryExpansionEnabled = false;  // Default OFF
  bool rerankingEnabled = false;       // Default OFF
  
  // Parameters  
  double chunkOverlapPercent = 0.15;   // 15% overlap
  double semanticWeight = 0.7;          // 70% semantic, 30% keyword
  int rerankTopK = 10;                  // Rerank top 10 candidates
}
```

---

#### [NEW] [query_expansion_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/query_expansion_service.dart)

Expands queries using LLM-based rephrasing:

```dart
class QueryExpansionService {
  /// Generates 2-3 rephrased variants of the original query
  Future<List<String>> expandQuery(String query);
  
  /// Merges results from all query variants using RRF
  Future<List<SearchResult>> searchWithExpandedQueries(
    String originalQuery,
    List<double> embedding,
  );
}
```

**Implementation approach**:
1. Use the active inference model to generate query variants
2. Prompt: "Rephrase this query in 2 different ways: {query}"
3. Run hybrid search for each variant
4. Merge results using existing RRF algorithm

---

#### [NEW] [reranking_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/reranking_service.dart)

LLM-based relevance scoring:

```dart
class RerankingService {
  /// Rerank chunks by generating relevance scores using LLM
  Future<List<SearchResult>> rerank(
    String query,
    List<SearchResult> candidates, {
    int topK = 5,
  });
}
```

**Implementation approach**:
1. Take top-K candidates from initial retrieval (default: 10)
2. For each candidate, prompt LLM: "Rate relevance 1-10 for query: {query}\nDocument: {chunk}"
3. Parse scores and re-sort by relevance
4. Return top-N results (default: 3-5)

---

### Existing Service Modifications

#### [MODIFY] [rag_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_service.dart)

**Chunk Overlap (Lines 311-358)**

```diff
- List<String> _splitIntoChunks(String text, int targetWords) {
-   const maxChars = 500;
+ List<String> _splitIntoChunks(
+   String text, 
+   int targetWords, {
+   double overlapPercent = 0.15,
+ }) {
+   const maxChars = 500;
+   final overlapChars = (maxChars * overlapPercent).round();
    ...
+   // Add overlap from previous chunk
+   if (chunks.isNotEmpty && overlapChars > 0) {
+     final prevChunk = chunks.last;
+     final overlap = prevChunk.substring(
+       max(0, prevChunk.length - overlapChars),
+     );
+     buffer.write(overlap);
+   }
```

**Query Expansion Integration (Lines 55-100)**

```diff
  Future<RAGResult> askWithRAG(String query, ...) async {
+   final settings = locator<RagSettingsService>();
+   
+   // Query expansion (if enabled)
+   List<String> queryVariants = [query];
+   if (settings.queryExpansionEnabled) {
+     final expansionService = locator<QueryExpansionService>();
+     queryVariants = await expansionService.expandQuery(query);
+   }
+   
    final queryEmbedding = await _embeddingService.generateEmbedding(query);
-   final searchResults = await _vectorStore.hybridSearch(...);
+   
+   // Search with all query variants
+   var searchResults = <SearchResult>[];
+   for (final variant in queryVariants) {
+     final variantEmbedding = await _embeddingService.generateEmbedding(variant);
+     final results = await _vectorStore.hybridSearch(variant, variantEmbedding);
+     searchResults.addAll(results);
+   }
+   searchResults = _deduplicateAndMerge(searchResults);
+   
+   // Reranking (if enabled)
+   if (settings.rerankingEnabled) {
+     final rerankService = locator<RerankingService>();
+     searchResults = await rerankService.rerank(query, searchResults);
+   }
```

**Add RAG Metrics for new steps**

```diff
  class RAGMetrics {
    RAGMetrics({
      required this.embeddingTime,
      required this.searchTime,
      required this.generationTime,
      required this.chunksRetrieved,
+     this.queryExpansionTime,
+     this.rerankingTime,
+     this.expandedQueryCount,
    });
```

---

#### [MODIFY] [vector_store.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/vector_store.dart)

**Add configurable semantic weight parameter**

```diff
  Future<List<SearchResult>> hybridSearch(
    String query,
    List<double> queryEmbedding, {
    int limit = 5,
-   double semanticWeight = 0.7,
+   double? semanticWeight,
  }) async {
+   final settings = locator<RagSettingsService>();
+   final weight = semanticWeight ?? settings.semanticWeight;
```

---

### Settings UI Enhancement

#### [MODIFY] [settings_view.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/settings/settings_view.dart)

Add new "RAG Quality" section with:

```dart
// New section after AI Model Management
const Text('RAG Quality Settings', ...),
const SizedBox(height: 16),

// Toggle switches
SwitchListTile(
  title: Text('Query Expansion'),
  subtitle: Text('Generate query variants for better recall'),
  value: viewModel.queryExpansionEnabled,
  onChanged: viewModel.toggleQueryExpansion,
),

SwitchListTile(
  title: Text('LLM Reranking'),
  subtitle: Text('Use AI to reorder results by relevance'),
  value: viewModel.rerankingEnabled,
  onChanged: viewModel.toggleReranking,
),

// Sliders
ListTile(
  title: Text('Chunk Overlap: ${viewModel.chunkOverlapPercent}%'),
  subtitle: Slider(
    value: viewModel.chunkOverlapPercent,
    min: 0,
    max: 30,
    divisions: 6,
    onChanged: viewModel.setChunkOverlap,
  ),
),

ListTile(
  title: Text('Semantic vs Keyword: ${viewModel.semanticWeight}'),
  subtitle: Slider(
    value: viewModel.semanticWeight,
    min: 0,
    max: 1,
    divisions: 10,
    onChanged: viewModel.setSemanticWeight,
  ),
),
```

#### [MODIFY] [settings_viewmodel.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/settings/settings_viewmodel.dart)

```dart
class SettingsViewModel extends BaseViewModel {
  final RagSettingsService _ragSettings = locator<RagSettingsService>();
  
  bool get queryExpansionEnabled => _ragSettings.queryExpansionEnabled;
  bool get rerankingEnabled => _ragSettings.rerankingEnabled;
  double get chunkOverlapPercent => _ragSettings.chunkOverlapPercent * 100;
  double get semanticWeight => _ragSettings.semanticWeight;
  
  void toggleQueryExpansion(bool value) { ... }
  void toggleReranking(bool value) { ... }
  void setChunkOverlap(double value) { ... }
  void setSemanticWeight(double value) { ... }
}
```

---

### Dependency Registration

#### [MODIFY] [app.locator.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/app/app.locator.dart)

```dart
locator.registerLazySingleton(() => RagSettingsService());
locator.registerLazySingleton(() => QueryExpansionService());
locator.registerLazySingleton(() => RerankingService());
```

---

## Verification Plan

### Automated Tests

#### Existing Tests to Update

| Test File | Command | Updates Required |
|-----------|---------|-----------------|
| [vector_store_test.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/test/services/vector_store_test.dart) | `flutter test test/services/vector_store_test.dart` | Add tests for configurable semantic weight |

#### New Tests to Create

| Test File | Purpose |
|-----------|---------|
| `test/services/rag_settings_service_test.dart` | Test preference persistence |
| `test/services/query_expansion_service_test.dart` | Test query variant generation |
| `test/services/reranking_service_test.dart` | Test relevance scoring |
| `test/services/rag_service_test.dart` | Test chunk overlap, integration |

**Run all tests:**
```bash
cd /media/limcheekin/My\ Passport/ws/rag.wtf/offline_sync
flutter test
```

### Manual Verification

1. **Settings UI**: 
   - Navigate to Settings → Verify "RAG Quality Settings" section appears
   - Toggle switches and sliders → Verify values persist after app restart

2. **Chunk Overlap**:
   - Ingest a document with related content spanning multiple chunks
   - Query for content near chunk boundaries → Verify improved context retrieval

3. **Query Expansion** (when enabled):
   - Ask a short/vague query → Observe expanded variants in metrics
   - Verify increased recall compared to single query

4. **Reranking** (when enabled):
   - Query documents → Verify reordered results in sources panel
   - Verify metrics show reranking time
