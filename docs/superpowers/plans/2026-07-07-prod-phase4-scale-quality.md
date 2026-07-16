# Phase 4 — Scale & Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
> Master plan: [2026-07-07-production-readiness-remediation.md](2026-07-07-production-readiness-remediation.md).

**Goal:** Make the RAG core scale to real corpora, fix retrieval-ranking correctness, wire dead settings, close remaining privacy/logging/UX gaps, and add the critical-path test coverage the audit flagged.

**Architecture:** Ranking/token/parse fixes are unit-testable logic. The vector-scan fix (C-3) is a search-path refactor. Ingestion-memory fixes stream inserts. The remaining Lows are batched by area (config/deps, UI polish). Test coverage is added last against the now-stable code.

**Tech Stack:** sqlite3 (FTS5 candidate pre-filter), Dart isolates (`compute`), mocktail, flutter_gemma.

## Global Constraints

See master plan. Phase-specific:
- Ranking changes MUST preserve existing green tests; where a test encodes buggy behavior, update it in the same task with a comment explaining the correction.
- C-3 MUST NOT change public search signatures (`hybridSearch`, `SearchResult`) — tests and viewmodels depend on them.

---

## Task 1: Fix query-expansion RRF to use per-list rank (H-4)

**Shape:** Logic (real unit test).

**Files:**
- Modify: `lib/services/query_expansion_service.dart` (`searchWithExpandedQueries` `:66-90`, `_mergeResultsWithRRF` `:92-123`)
- Test: `test/services/query_expansion_service_test.dart`

**Why:** RRF score `1.0/(k + i + 1)` uses the **global** index `i` into the concatenated results (`:102-104`; list built by `addAll` per variant at `:85`), so all results from the first variant systematically outrank later variants regardless of intra-list rank. `VectorStore.mergeResults` (`:508-545`) does RRF correctly with per-list ranks — mirror that.

**Interfaces:**
- Change: `searchWithExpandedQueries` collects results **per variant** (a `List<List<SearchResult>>`) and passes them to a rank-aware merge.

- [ ] **Step 1: Write the failing test**

The test must use **disjoint** items so buggy (global-index) and fixed (per-list-rank) RRF give *different* answers — otherwise it passes on both and isn't a real red-green anchor. Arrange variant "orig"→`[A, B]` and variant "alt"→`[C, D]` (all distinct). Assert that **C** (rank 0 in the second list) outranks **B** (rank 1 in the first list):
```dart
test('RRF fuses by per-list rank, not concatenation index', () async {
  // orig -> [A(rank0), B(rank1)]   alt -> [C(rank0), D(rank1)]
  // Buggy global index: A=1/61, B=1/62, C=1/63, D=1/64  -> B outranks C (WRONG).
  // Fixed per-list rank: A=C=1/61, B=D=1/62            -> C outranks B (RIGHT).
  // Stub embedding + vectorStore.hybridSearch to return those two lists per variant.
  final fused = await service.searchWithExpandedQueries(
    'orig', ['orig', 'alt'], limit: 4);
  final bIndex = fused.indexWhere((r) => r.id == 'B');
  final cIndex = fused.indexWhere((r) => r.id == 'C');
  expect(cIndex, lessThan(bIndex)); // C ranks above B only with the fix
});
```
(Wire the mocks so `hybridSearch(variant='orig',…)` returns `[A,B]` and `hybridSearch(variant='alt',…)` returns `[C,D]`.)

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/query_expansion_service_test.dart`
Expected: FAIL — with global-index RRF, B (global index 1) outranks C (global index 2), so `cIndex < bIndex` is false.

- [ ] **Step 3: Collect per-variant lists and fuse by intra-list rank**

In `lib/services/query_expansion_service.dart`, change `searchWithExpandedQueries` (`:73-89`) to keep lists separate:
```dart
    final resultLists = <List<SearchResult>>[];
    for (final variant in queryVariants) {
      final embedding = await _embeddingService.generateEmbedding(variant);
      final results = await _vectorStore.hybridSearch(
        variant, embedding,
        limit: limit * 2, semanticWeight: semanticWeight, documentIds: documentIds,
      );
      resultLists.add(results);
    }
    return _mergeResultsWithRRF(resultLists, limit);
```
Change `_mergeResultsWithRRF` (`:92-123`) to accept `List<List<SearchResult>>` and use each result's rank **within its own list**:
```dart
  List<SearchResult> _mergeResultsWithRRF(
    List<List<SearchResult>> resultLists,
    int limit,
  ) {
    const k = RagConstants.rrfConstant;
    final scores = <String, double>{};
    final items = <String, SearchResult>{};

    for (final list in resultLists) {
      for (var rank = 0; rank < list.length; rank++) {
        final result = list[rank];
        scores[result.id] = (scores[result.id] ?? 0) + 1.0 / (k + rank + 1);
        items[result.id] ??= result;
      }
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(limit)
        .map((e) => SearchResult(
              id: e.key,
              content: items[e.key]!.content,
              score: e.value,
              metadata: items[e.key]!.metadata,
            ))
        .toList();
  }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/services/query_expansion_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/query_expansion_service.dart test/services/query_expansion_service_test.dart
git commit -m "fix(rag): RRF fuses expanded-query results by per-list rank"
```

---

## Task 2: Fix reranking score parsing of multi-number output (M-5)

**Shape:** Logic (real unit test).

**Files:**
- Modify: `lib/services/reranking_service.dart` (the parse block `:93-96` inside `_scoreRelevance`, which spans `:63-109`)
- Test: `test/services/reranking_service_test.dart`

**Why:** `replaceAll(RegExp('[^0-9.]'), '')` turns `"8/10"` into `"810"` → parses 810.0 → clamps to 10.0. Extract the first numeric token instead.

- [ ] **Step 1: Write the failing test**

Add to `test/services/reranking_service_test.dart` (in the `rerank` group, following the existing mock idiom): make the model return `"8/10"` and assert the candidate's score is `8.0`, not `10.0`:
```dart
test('parses "8/10" as 8.0, not 810 clamped to 10', () async {
  final candidates = [
    SearchResult(id: '1', content: 'c1', score: 0.5, metadata: {}),
  ];
  when(() => mockModelProvider.getModel())
      .thenAnswer((_) async => mockInferenceModel);
  final mockChat = MockInferenceChat();
  when(() => mockInferenceModel.createChat(temperature: any(named: 'temperature')))
      .thenAnswer((_) async => mockChat);
  when(mockChat.initSession).thenAnswer((_) async {});
  when(() => mockChat.addQuery(any())).thenAnswer((_) async {});
  when(mockChat.generateChatResponseAsync)
      .thenAnswer((_) => Stream.fromIterable([TextResponse('8/10')]));

  final results = await service.rerank('q', candidates, topK: 1);
  expect(results.first.score, 8.0);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/services/reranking_service_test.dart`
Expected: FAIL — score comes out `10.0` (810 clamped).

- [ ] **Step 3: Extract the first numeric token**

In `lib/services/reranking_service.dart`, replace the parse (`:93-96`):
```dart
      final scoreText = response.toString().trim();
      final match = RegExp(r'\d+(\.\d+)?').firstMatch(scoreText);
      final score = match != null ? double.tryParse(match.group(0)!) : null;
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/services/reranking_service_test.dart`
Expected: PASS (and the existing `8.0`/`9.5` test stays green).

- [ ] **Step 5: Commit**

```bash
git add lib/services/reranking_service.dart test/services/reranking_service_test.dart
git commit -m "fix(rerank): extract first numeric token from LLM score output"
```

---

## Task 3: Source token budget from the active model + honor settings (M-6), and fix streaming context count (M-3), redundant embed (M-13), metrics (M-12), negative budget (L-11)

**Shape:** Logic (real unit tests on rag_service). Batched — all live in `rag_service.dart`'s generation/budget path and share the same test surface.

**Files:**
- Modify: `lib/services/rag_service.dart` (`_generate` `:326-390`, `_generateStream` `:393-459`, `askWithRAG*` `:103-290`)
- Test: `test/services/rag_service_test.dart`

**Why:**
- **M-6:** Budget math uses `ModelConfig.allModels.firstWhere(type == inference, orElse: …)` → always the first entry (`gemma3_270M`, maxTokens 1024), regardless of the active model, and ignores `settings.maxTokens`. `inference_model_provider` already resolves the right value (`:29-38`).
- **M-3:** Streaming path hardcodes `limit: … : 3` (`:235,242`) and `take(3)` (`:260`) instead of `settings.searchTopK`.
- **M-13:** Query is always embedded up-front (`:129,225`) then discarded when expansion re-embeds every variant.
- **M-12:** `embeddingTime` includes expansion; `generationTime` folds in reranking.
- **L-11:** `availableForPrompt` (`:341,408`) can go negative on long queries.

**Interfaces:**
- Produces: a shared `@visibleForTesting int resolveMaxTokens(RagSettingsService)` helper on `RagService` (public-for-test so Step 1's unit test can assert on it).

- [ ] **Step 1: Write failing tests**

In `test/services/rag_service_test.dart`, add tests using the mock settings/token-manager helpers:
```dart
test('streaming path uses searchTopK, not hardcoded 3', () async {
  when(() => settings.searchTopK).thenReturn(2);
  when(() => settings.rerankingEnabled).thenReturn(false);
  when(() => settings.queryExpansionEnabled).thenReturn(false);
  // stub vectorStore.hybridSearch to capture the limit arg
  await ragService.askWithRAGStream('q').toList();
  final captured = verify(() => vectorStore.hybridSearch(any(), any(),
      limit: captureAny(named: 'limit'),
      semanticWeight: any(named: 'semanticWeight'),
      documentIds: any(named: 'documentIds'))).captured;
  expect(captured.single, 2); // was 3
});

test('resolveMaxTokens uses the active model, not the first catalog entry', () {
  when(() => settings.maxTokens).thenReturn(null);
  when(() => settings.activeInferenceModelId).thenReturn('gemma3-1b');
  // gemma3_1B.maxTokens == 2048; the buggy firstWhere returned 270M's 1024.
  expect(ragService.resolveMaxTokens(settings), 2048);
});
```
(Fill in stubs to the existing file's idiom. Key assertions: `limit == searchTopK` (M-3, observable via `captureAny`) and `resolveMaxTokens` returns the active model's value (M-6, observable because Step 3 marks it `@visibleForTesting`). The non-negative-budget clamp (L-11) is verified by **inspection** in Step 4 below, not a unit test — `availableForPrompt` is a local with no observable surface.)

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/services/rag_service_test.dart`
Expected: FAIL — streaming uses 3.

- [ ] **Step 3: Add the shared maxTokens resolver (M-6)**

In `lib/services/rag_service.dart`, add a method (import `package:flutter/foundation.dart` for `@visibleForTesting`):
```dart
  @visibleForTesting
  int resolveMaxTokens(RagSettingsService settings) {
    final userMaxTokens = settings.maxTokens;
    if (userMaxTokens != null) return userMaxTokens;
    final activeId = settings.activeInferenceModelId;
    final model = ModelConfig.allModels.firstWhere(
      (m) => m.id == activeId && m.type == AppModelType.inference,
      orElse: () => ModelConfig.allModels.firstWhere(
        (m) => m.type == AppModelType.inference,
        orElse: () => InferenceModels.gemma3_270M,
      ),
    );
    return model.maxTokens;
  }
```
Replace both budget blocks' `final maxTokens = modelConfig.maxTokens;` (derived from the `firstWhere` at `:332-338` and `:399-405`) with:
```dart
    final maxTokens = resolveMaxTokens(settings);
```
(Remove the now-unused `modelConfig` local in both `_generate` and `_generateStream`; pass `settings` in — both already `locator<RagSettingsService>()` internally.)

> **Critical — also fix the provider, or M-6 reopens.** The model is actually **loaded** by `InferenceModelProvider.getModel()` (`rag_service.dart:372,443`), whose `maxTokens` resolution (`inference_model_provider.dart:31-38`) has the **same buggy `firstWhere`** → always `gemma3_270M`'s 1024 when the user hasn't set `settings.maxTokens`. If only `rag_service` is patched, the budget becomes 2048 (active model) while the model is loaded with a 1024 context → the exact prompt-overflow M-6 warns of (today both agree at 1024; this patch would make them disagree). So **also** update `inference_model_provider.dart` to resolve by active-model id. Extract the shared logic: move `resolveMaxTokens` to a place both can call (e.g. a small `TokenBudget.resolveMaxTokens(settings)` static, or duplicate the identical active-id lookup in the provider's `_load`). In `inference_model_provider.dart:31-38`, replace the `firstWhere(type == inference, orElse: 270M)` with the active-id lookup:
```dart
      final maxTokens = userMaxTokens ?? _maxTokensForActiveModel(settings);
```
where `_maxTokensForActiveModel` reads `settings.activeInferenceModelId` and falls back to the first inference model only if the id is unknown. Add a test asserting the provider's resolved `maxTokens` matches `rag_service.resolveMaxTokens` for the same active id.

- [ ] **Step 4: Clamp the budget (L-11)**

In both `_generate` (`:341`) and `_generateStream` (`:408`):
```dart
    final availableForPrompt =
        (maxTokens - outputReserve - queryTokens).clamp(0, maxTokens);
```
If it clamps to 0, `_buildContextWithBudget` already returns "No relevant context found." — add a `LoggingService.warning` when `availableForPrompt == 0`.

- [ ] **Step 5: Use searchTopK in the streaming path (M-3)**

In `askWithRAGStream` (`:235,242`), replace `settings.rerankingEnabled ? settings.rerankTopK : 3` with `settings.rerankingEnabled ? settings.rerankTopK : settings.searchTopK`. Replace `searchResults.take(3)` (`:260`) with `searchResults.take(settings.searchTopK)`.

- [ ] **Step 6: Skip redundant up-front embed on expansion path (M-13)**

The embed-skip guard MUST mirror the **exact** branch condition that consumes `queryEmbedding`, not just `queryExpansionEnabled`. The consuming `else` branch runs when `!(settings.queryExpansionEnabled && queryVariants.length > 1)` (`:134`, `:230`). If you guard only on `queryExpansionEnabled`, then when expansion is ON but `expandQuery` returns a single variant — its documented on-error fallback `[query]` (`query_expansion_service.dart:61`) — `queryVariants.length == 1`, so the `else` branch executes and dereferences a **null** `queryEmbedding` → crash. Compute the branch condition once, after expansion, and guard on it:
```dart
    // queryVariants is already set (expansion ran above, or is [query]).
    final useExpansion =
        settings.queryExpansionEnabled && queryVariants.length > 1;

    // Only embed up-front for the non-expansion branch (expansion re-embeds
    // each variant inside searchWithExpandedQueries).
    List<double>? queryEmbedding;
    if (!useExpansion) {
      queryEmbedding = await _embeddingService.generateEmbedding(query);
    }
    // ... then: if (useExpansion) { searchWithExpandedQueries(...) }
    //           else { hybridSearch(query, queryEmbedding!, ...) }
```
Use the same `useExpansion` local for the `if/else` search dispatch (replacing the inline `settings.queryExpansionEnabled && queryVariants.length > 1` at `:134`/`:230`) so the guard and the branch can never diverge. Adjust `embeddingTime` to be measured only around this call. Apply identically in `askWithRAG` and `askWithRAGStream`.

- [ ] **Step 7: Attribute metrics per stage (M-12)**

Capture explicit start/stop deltas so `embeddingTime` excludes expansion and `generationTime` excludes reranking. Introduce local stopwatch marks around each stage (expansion, embedding, search, rerank, generation) and compute each `Duration` as the delta of its own span rather than cumulative subtraction.

- [ ] **Step 8: Run tests**

Run: `flutter test test/services/rag_service_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/services/rag_service.dart test/services/rag_service_test.dart
git commit -m "fix(rag): active-model token budget, searchTopK streaming, no redundant embed, per-stage metrics, non-negative budget"
```

---

## Task 4: Restrict semantic scan to candidate ids (C-3)

**Shape:** Perf refactor (real test asserting behavior + correctness preserved).

**Files:**
- Modify: `lib/services/vector_store.dart` (`hybridSearch` `:172-206`, `_semanticSearchAsync` `:208-243`)
- Test: `test/services/vector_store_test.dart`

**Why:** `SELECT id, content, embedding, metadata FROM vectors` (`:215`) has no `LIMIT`; every default query reads **all** rows, JSON-decodes every embedding, and serializes the full dataset to a `compute` isolate. Latency/memory grow linearly with corpus size. Fix: scope the semantic scan to the FTS candidate ids (hybrid pre-filter). The keyword search already fetches up to 100 candidates (`:187`); reuse their ids to bound the semantic scan.

**Interfaces:**
- Change: `_semanticSearchAsync` accepts an optional `Set<String>? candidateIds`; `hybridSearch` passes the ids from `keywordResults` (union with any `documentIds` filter).

- [ ] **Step 1: Write the failing/guarding test**

Add to `test/services/vector_store_test.dart` a test that inserts, say, 3 rows where only 2 match the keyword query, and asserts the semantic path is scoped (behaviorally: results still correct, and — if we expose a debug counter — rows scanned ≤ candidates). Since we won't expose internals, assert correctness is preserved AND add a large-corpus timing smoke check is out of scope; the behavioral test:
```dart
test('hybrid search still returns keyword+semantic matches after candidate scoping', () async {
  vectorStore.insertEmbedding(id: 'a', documentId: 'd', content: 'alpha fox', embedding: [1,0,0]);
  vectorStore.insertEmbedding(id: 'b', documentId: 'd', content: 'beta dog', embedding: [0,1,0]);
  vectorStore.insertEmbedding(id: 'c', documentId: 'd', content: 'gamma cat', embedding: [0,0,1]);
  final results = await vectorStore.hybridSearch('fox', [1,0,0], limit: 3);
  expect(results.map((r) => r.id), contains('a'));
});
```

- [ ] **Step 2: Run it to confirm current behavior (baseline green)**

Run: `flutter test test/services/vector_store_test.dart`
Expected: PASS today (this test guards against regressions from the refactor).

- [ ] **Step 3: Scope the semantic scan to candidate ids**

In `lib/services/vector_store.dart`, change `hybridSearch` (`:194-198`) to collect candidate ids from the keyword results and pass them down:
```dart
    final candidateIds = keywordResults.map((r) => r.id).toSet();
    final semanticResults = await _semanticSearchAsync(
      queryEmbedding,
      limit: limit * 2,
      documentIds: documentIds,
      candidateIds: candidateIds.isEmpty ? null : candidateIds,
    );
```
In `_semanticSearchAsync` (`:208-224`), add the parameter and an `id IN (...)` clause:
```dart
  Future<List<SearchResult>> _semanticSearchAsync(
    List<double> embedding, {
    required int limit,
    List<String>? documentIds,
    Set<String>? candidateIds,
  }) async {
    var sql = 'SELECT id, content, embedding, metadata FROM vectors';
    final where = <String>[];
    var params = <Object?>[];

    if (documentIds != null && documentIds.isNotEmpty) {
      where.add('document_id IN (${List.filled(documentIds.length, '?').join(', ')})');
      params.addAll(documentIds);
    }
    if (candidateIds != null && candidateIds.isNotEmpty) {
      where.add('id IN (${List.filled(candidateIds.length, '?').join(', ')})');
      params.addAll(candidateIds);
    }
    if (where.isNotEmpty) sql += ' WHERE ${where.join(' AND ')}';
    // Bound the scan even in the fallback (no candidates) case.
    sql += ' LIMIT 500';

    final rows = _db!.select(sql, params);
    // ... existing data mapping + compute(...) unchanged ...
```
> **Correctness/recall tradeoff — read before implementing.** Scoping the semantic scan to FTS candidate ids is the audit's recommended hybrid pre-filter, but it **changes recall**: a chunk that is semantically relevant yet shares *no keyword* with the query (previously surfaced by the full semantic scan) is dropped whenever `keywordResults` is non-empty — hybrid search effectively becomes semantic re-ranking of the keyword pool. This is usually acceptable (the pool is 100 candidates) but is a real behavior change. Two mitigations, pick per product judgment:
> - **Widen the keyword candidate pool** (e.g. 100 → 200) so semantic-relevant items are more likely to be in the pool, and/or
> - **Union** the candidate ids with a small bounded pure-semantic top-N (a capped extra scan) so strong semantic-only matches still surface.
>
> The Step 1 guard test only asserts `contains('a')`, so it will **not** catch this recall regression — add a second test: insert a row that matches the query **semantically but not by keyword**, and assert it still appears (choosing whichever mitigation you adopt). Also: the pure-semantic fallback (no keyword hits) uses `LIMIT 500` with **no `ORDER BY`**, an arbitrary cap — per the audit's "no silent caps" guidance, `LoggingService.debug` when the 500 cap is hit and document the cap + recall tradeoff in a code comment.

- [ ] **Step 4: Run the test to confirm it still passes**

Run: `flutter test test/services/vector_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/vector_store.dart test/services/vector_store_test.dart
git commit -m "perf(search): scope semantic scan to FTS candidates + bounded fallback"
```

---

## Task 5: Batch reranking into one scoring prompt (H-2)

**Shape:** Logic (unit test on reranking).

**Files:**
- Modify: `lib/services/reranking_service.dart` (`rerank` `:13-60`, `_scoreRelevance` `:63-109`)
- Test: `test/services/reranking_service_test.dart`
- Reference: `lib/services/rag_constants.dart:29` (`maxCharsForReranking`) — use it (L-8)

**Why:** `rerank` issues one full model generation per candidate, serially (`:26-34`) — `rerankTopK` extra generations per query. Batch all candidates into a single scoring prompt that returns one score per line, and use `RagConstants.maxCharsForReranking` instead of the hardcoded `500` (`:75`, L-8).

- [ ] **Step 1: Write the failing test**

Add to `test/services/reranking_service_test.dart`: two candidates, model returns a two-line response `"9.5\n8.0"` from a **single** generation; assert results are ordered `[c2(9.5), c1(8.0)]` and that `generateChatResponseAsync` was invoked once:
```dart
test('reranks all candidates with a single batched generation', () async {
  final candidates = [
    SearchResult(id: '1', content: 'c1', score: 0.1, metadata: {}),
    SearchResult(id: '2', content: 'c2', score: 0.2, metadata: {}),
  ];
  when(() => mockModelProvider.getModel()).thenAnswer((_) async => mockInferenceModel);
  final mockChat = MockInferenceChat();
  when(() => mockInferenceModel.createChat(temperature: any(named: 'temperature')))
      .thenAnswer((_) async => mockChat);
  when(mockChat.initSession).thenAnswer((_) async {});
  when(() => mockChat.addQuery(any())).thenAnswer((_) async {});
  when(mockChat.generateChatResponseAsync)
      .thenAnswer((_) => Stream.fromIterable([TextResponse('8.0\n9.5')]));

  final results = await service.rerank('q', candidates, topK: 2);
  expect(results.first.id, '2');
  verify(mockChat.generateChatResponseAsync).called(1);
});
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/services/reranking_service_test.dart`
Expected: FAIL — current code generates once per candidate (`called(2)`).

- [ ] **Step 3: Implement batched scoring**

Replace the per-candidate loop in `rerank` with one call that builds a numbered prompt over all `topK` candidates and parses one numeric token per line (reusing Task 2's first-numeric-token extraction per line). Truncate each candidate's content to `RagConstants.maxCharsForReranking`. On parse-count mismatch (fewer scores than candidates), fall back to original order (log it). Keep the existing outer try/catch returning `candidates` on error. Preserve the timeout from Phase 3 Task 5.

- [ ] **Step 4: Run tests**

Run: `flutter test test/services/reranking_service_test.dart`
Expected: PASS (batched + existing tests green; update the old per-candidate test's mock to a single multi-line response with a comment noting the batching change).

- [ ] **Step 5: Commit**

```bash
git add lib/services/reranking_service.dart test/services/reranking_service_test.dart
git commit -m "perf(rerank): score all candidates in one batched prompt; use maxCharsForReranking"
```

---

## Task 6: Record chunk offsets to avoid O(n·m) window search + bound concurrency (H-3)

**Shape:** Logic (unit test on contextual retrieval).

**Files:**
- Modify: `lib/services/contextual_retrieval_service.dart` (`contextualizeDocument` `:111-145`, `_getRelevantWindow` `:147-156`)
- Modify: `lib/services/smart_chunker.dart` (return offsets) OR compute offsets once in `contextualizeDocument`
- Test: `test/services/contextual_retrieval_service_test.dart`

**Why:** One model call per chunk, serial (`:120-142`); `fullDoc.indexOf(chunk)` per chunk (`:148`) is O(chunks × docLen). Ingesting one large document can take minutes with no cancel.

> **Testability:** `contextualizeDocument` → `generateChunkContext` calls the **static, non-injectable** `FlutterGemma.getActiveModel()`, so the full method can't be driven deterministically, and the window/offset is not exposed on any public type. So the red-green anchor must be a **pure, `@visibleForTesting` offset function** — assert on that, not on `contextualizeDocument`.

- [ ] **Step 1: Write the failing test (on the extracted offset function)**

Add to `test/services/contextual_retrieval_service_test.dart`:
```dart
test('computeChunkOffsets resolves duplicate chunk text to sequential positions', () {
  const doc = 'foo BODY bar BODY baz';
  final offsets = service.computeChunkOffsets(doc, ['BODY', 'BODY']);
  expect(offsets[0], 4);   // first "BODY"
  expect(offsets[1], 13);  // second "BODY" — NOT the first occurrence again
});
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/services/contextual_retrieval_service_test.dart`
Expected: FAIL — `computeChunkOffsets` does not exist (compile error).

- [ ] **Step 3: Extract a pure forward-pass offset function + use it**

Add a `@visibleForTesting` method (import `package:flutter/foundation.dart`) computing each chunk's start in one forward pass:
```dart
  @visibleForTesting
  List<int> computeChunkOffsets(String documentContent, List<String> chunks) {
    final offsets = <int>[];
    var cursor = 0;
    for (final chunk in chunks) {
      final idx = documentContent.indexOf(chunk, cursor);
      final start = idx == -1 ? cursor : idx;
      offsets.add(start);
      cursor = start + chunk.length;
    }
    return offsets;
  }
```
In `contextualizeDocument`, call `computeChunkOffsets(documentContent, chunks)` once before the loop, and replace `_getRelevantWindow(documentContent, chunk, maxChars)` (`:125`) with a window computed from the precomputed `offsets[i]`:
```dart
  String _windowAt(String fullDoc, int chunkStart, int maxChars) {
    final windowStart = max(0, chunkStart - maxChars ~/ 2);
    final windowEnd = min(fullDoc.length, windowStart + maxChars);
    return fullDoc.substring(windowStart, windowEnd);
  }
```
Use `offsets[i]` in the loop. This removes the O(n·m) repeated `indexOf` scan and is deterministically testable via `computeChunkOffsets`.

- [ ] **Step 4: Bound concurrency (optional, safe)**

The per-chunk generations remain serial by default (on-device inference is memory-bound; parallelizing risks OOM). Keep serial but ensure the Phase 3 timeout applies and `onProgress` still fires — do not increase concurrency beyond 1 without device-tier gating. Note this decision in a comment.

- [ ] **Step 5: Run tests**

Run: `flutter test test/services/contextual_retrieval_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/contextual_retrieval_service.dart test/services/contextual_retrieval_service_test.dart
git commit -m "perf(contextual): precompute chunk offsets, drop per-chunk indexOf scan"
```

---

## Task 7: Wire chunk-overlap setting to the active chunker; delete dead RagService ingestion path (M-25)

**Shape:** Logic (unit test on smart_chunker) + dead-code deletion.

**Files:**
- Modify: `lib/services/smart_chunker.dart` (`chunk` `:13-17`)
- Modify: `lib/services/document_management_service.dart` (`_parseAndChunk` `:422-446` — pass overlap)
- Delete: `lib/services/rag_service.dart` `ingestDocument` (`:292-324`) and `splitIntoChunks` (`:465-547`) — dead code
- Test: `test/services/smart_chunker_test.dart`

**Why:** The active path is `SmartChunker.chunk()` (called from the parse isolate at `document_management_service.dart:438`), which hardcodes `overlapChars = 50` and never reads `chunkOverlapPercent`. The only consumer of the setting is `RagService.splitIntoChunks` via `RagService.ingestDocument` — which is **never invoked anywhere** (dead code). Result: the Settings chunk-overlap slider does nothing.

- [ ] **Step 1: Confirm the dead code has no callers**

Run:
```bash
grep -rn "ingestDocument\|splitIntoChunks" lib test
```
Expected: references only inside `rag_service.dart` itself and its test (if any). Confirm no production caller. If `rag_service_test.dart` tests `splitIntoChunks`, those tests move/delete with the method.

- [ ] **Step 2: Write the failing test (overlap honored)**

Add to `test/services/smart_chunker_test.dart`: chunk a long text with `overlapChars` derived from a percent, and assert consecutive chunks share the expected overlap length (distinct from the old hardcoded 50):
```dart
test('chunk honors provided overlapChars', () {
  final text = 'A' * 1200; // forces multiple chunks at maxChars=500
  final chunks = SmartChunker().chunk(text, overlapChars: 100);
  expect(chunks.length, greaterThan(1));
  // consecutive chunks overlap by ~100 chars (implementation-defined tail)
});
```

- [ ] **Step 3: Pass the setting through the ingest path**

`SmartChunker.chunk` already accepts `overlapChars` (`:16`). The isolate entrypoint `_parseAndChunk` (`document_management_service.dart:438`) calls `chunker.chunk(parsed.content)` with the default 50. Thread the setting: read `_settingsService.chunkOverlapPercent` in `_processIngestion` and pass it into `parseParams`, then compute `overlapChars = (RagConstants.maxCharsPerChunk * overlapPercent).round()` inside `_parseAndChunk`:
```dart
  final overlapPercent = (params['overlapPercent'] as double?) ?? 0.15;
  final overlapChars = (RagConstants.maxCharsPerChunk * overlapPercent).round();
  final chunks = chunker.chunk(parsed.content, overlapChars: overlapChars);
```
Add `'overlapPercent': _settingsService.chunkOverlapPercent` to both `parseParams` maps in `addDocument` (`:121`) and `addDocumentFromPlatformFile` (`:157-160`). Import `RagConstants` in `document_management_service.dart`.

- [ ] **Step 4: Delete the dead RagService ingestion/chunking code**

Remove `RagService.ingestDocument` (`:292-324`) and `RagService.splitIntoChunks` (`:465-547`) and any now-unused imports/`@visibleForTesting`. Remove/relocate their tests. Add a `step >= 1` guard is now moot here (that code is gone) — see L-22 which covers the surviving `smart_chunker` path.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/services/smart_chunker_test.dart test/services/rag_service_test.dart && flutter analyze`
Expected: PASS; analyze clean (no unused-symbol warnings from the deletion).

- [ ] **Step 6: Commit**

```bash
git add lib/services/smart_chunker.dart lib/services/document_management_service.dart lib/services/rag_service.dart test/services/smart_chunker_test.dart test/services/rag_service_test.dart
git commit -m "fix(ingest): wire chunk-overlap setting to SmartChunker; delete dead RagService ingestion path"
```

---

## Task 8: Guard smart_chunker step >= 1 (L-22) + clamp settings on read (L-24, L-10)

**Shape:** Logic (unit tests). Batched — all defend the chunk/settings read path.

**Files:**
- Modify: `lib/services/smart_chunker.dart` (`_hardChop` `:193-200`)
- Modify: `lib/services/rag_settings_service.dart` (`initialize` `:41-59`)
- Test: `test/services/smart_chunker_test.dart`, `test/services/rag_settings_service_test.dart` (new)

**Why:**
- **L-22:** `for (var i = 0; i < text.length; i += maxChars - overlapChars)` (`smart_chunker.dart:195`) infinite-loops if `overlapChars >= maxChars`. Unreachable via UI today but defense-in-depth.
- **L-24:** `initialize()` reads persisted settings with **no clamping** (`:44-58`); a tampered/older prefs file loads raw, bypassing every write-time clamp.
- **L-10:** `semanticWeight` in particular escapes [0,1] via this read path, which would invert ranking.

- [ ] **Step 1: Write failing tests**

`smart_chunker_test.dart`:
```dart
test('_hardChop does not hang when overlap >= maxChars', () {
  // large single line, pathological overlap
  final chunks = SmartChunker().chunk('B' * 2000, maxChars: 100, overlapChars: 100);
  expect(chunks, isNotEmpty); // must terminate
});
```
`rag_settings_service_test.dart` (new — service was only ever mocked; audit gap): set mock prefs with out-of-range values, call `initialize`, assert getters are clamped:
```dart
test('initialize clamps out-of-range persisted values', () async {
  SharedPreferences.setMockInitialValues({
    'rag_semantic_weight': 5.0,
    'rag_search_top_k': 99,
    'rag_chunk_overlap_percent': 0.9,
  });
  final s = RagSettingsService();
  await s.initialize();
  expect(s.semanticWeight, inInclusiveRange(0.0, 1.0));
  expect(s.searchTopK, inInclusiveRange(1, 5));
  expect(s.chunkOverlapPercent, inInclusiveRange(0.0, 0.3));
});
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/services/smart_chunker_test.dart test/services/rag_settings_service_test.dart`
Expected: FAIL — hang/timeout on chunker; unclamped settings.

- [ ] **Step 3: Guard the step (L-22)**

In `lib/services/smart_chunker.dart` `_hardChop` (`:195`):
```dart
    final step = (maxChars - overlapChars) < 1 ? 1 : (maxChars - overlapChars);
    for (var i = 0; i < text.length; i += step) {
```

- [ ] **Step 4: Clamp on read (L-24, L-10)**

In `lib/services/rag_settings_service.dart` `initialize()` (`:46-50,56`), clamp each read to match the setters' ranges:
```dart
    _chunkOverlapPercent = (prefs.getDouble(_keyChunkOverlap) ?? 0.15).clamp(0.0, 0.3);
    _semanticWeight = (prefs.getDouble(_keySemanticWeight) ?? 0.7).clamp(0.0, 1.0);
    _rerankTopK = (prefs.getInt(_keyRerankTopK) ?? 10).clamp(5, 20);
    _searchTopK = (prefs.getInt(_keySearchTopK) ?? 2).clamp(1, 5);
    _maxHistoryMessages = (prefs.getInt(_keyMaxHistoryMessages) ?? 2).clamp(0, 5);
    _maxDocumentSizeMB = (prefs.getInt(_keyMaxDocumentSizeMB) ?? 10).clamp(1, 50);
```
(`_maxTokens` stays nullable; if non-null, clamp to `512..8192`.)

- [ ] **Step 5: Run tests**

Run: `flutter test test/services/smart_chunker_test.dart test/services/rag_settings_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/smart_chunker.dart lib/services/rag_settings_service.dart test/services/smart_chunker_test.dart test/services/rag_settings_service_test.dart
git commit -m "fix: guard chunker step>=1; clamp all settings on read"
```

---

## Task 9: Stream embeddings to DB incrementally + parser size guard + off-isolate byte hashing (M-14, M-15, M-16)

**Shape:** Logic/perf. Batched — all reduce ingestion peak memory / main-isolate work.

**Files:**
- Modify: `lib/services/document_management_service.dart` (`_processIngestion` embed loop `:242-291`, byte hash `:143`)
- Modify: `lib/services/document_parser_service.dart` (`parseDocumentFromBytes` `:65-75`)
- Test: `test/services/document_management_service_test.dart`

**Why:**
- **M-14:** Peak memory ≈ file bytes + full text + all chunk strings + all embedding vectors at once; embeddings accumulate in a single `embeddingDataList` and insert only at the end (`:291`).
- **M-15:** The parser enforces no size limit itself; size checks live only in the caller. The parser is also constructed fresh inside the isolate (`:425`).
- **M-16:** `sha256.convert(bytes)` for byte uploads runs synchronously on the UI thread (`:143`); the file-path route streams correctly (`:397`).

- [ ] **Step 1: Insert embeddings per batch (M-14)**

In `_processIngestion`, move `_vectorStore.insertEmbeddingsBatch(batchResults)` **inside** the batch loop (after each `await Future.wait(futures)` at `:284`) instead of accumulating into `embeddingDataList` and inserting once at `:291`. This caps live embedding vectors at one batch (10) rather than the whole document. Update `chunkCount` from the running count.

- [ ] **Step 2: Add a max-bytes guard in the parser (M-15)**

In `document_parser_service.dart` `parseDocumentFromBytes` (`:65-68`), add an internal ceiling as defense-in-depth (independent of the caller's per-settings limit):
```dart
    const maxBytes = 50 * 1024 * 1024; // hard ceiling; caller enforces user limit
    if (bytes.length > maxBytes) {
      throw Exception('Document exceeds maximum supported size');
    }
```

- [ ] **Step 3: Hash byte uploads off the UI isolate (M-16)**

In `addDocumentFromPlatformFile` (`:143`), replace the synchronous hash with a `compute`:
```dart
    final hash = await compute(_sha256Hex, bytes);
```
Add a top-level helper (near `_parseAndChunk`):
```dart
String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
```

- [ ] **Step 4: Write/adjust tests**

Put the parser size-guard assertion in **`document_parser_service_test.dart`** (call `parseDocumentFromBytes` directly with an oversized `Uint8List` and expect a throw) — NOT in the service test: `DocumentManagementService`'s own `maxDocumentSizeMB` check (≤50 MB, `:96,136`) fires *before* the parser's 50 MB guard, so the guard is never reached through the service path. In `document_management_service_test.dart`, assert instead that small-doc ingestion still succeeds via the new per-batch insert path. Keep existing tests green.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/services/document_management_service_test.dart test/services/document_parser_service_test.dart && flutter analyze`
Expected: PASS; clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/document_management_service.dart lib/services/document_parser_service.dart test/services/document_management_service_test.dart
git commit -m "perf(ingest): incremental batch inserts, parser size guard, off-isolate byte hashing"
```

---

## Task 10: Persist settings sliders on change-end, not every tick (M-17)

**Shape:** Config/UI. Verification = sliders gain `onChangeEnd`; analyze clean.

**Files:**
- Modify: `lib/ui/views/settings/settings_view.dart` (sliders `:300-385`)
- Modify: `lib/ui/views/settings/settings_viewmodel.dart` (add transient value + persist method)

**Why:** Sliders supply only `onChanged` (`:307,319,352,365,383`); each setter awaits a `SharedPreferences` write + `notifyListeners()` per drag tick → storage churn and jank. Update a transient value on `onChanged`, persist on `onChangeEnd`.

- [ ] **Step 1: Add transient values + persist-on-end in the viewmodel**

In `settings_viewmodel.dart`, for each slider setting add a transient backing field updated synchronously on drag and a persist call for change-end. Example for chunk overlap:
```dart
  double? _pendingChunkOverlap;
  double get chunkOverlapDisplay =>
      _pendingChunkOverlap ?? (_ragSettings.chunkOverlapPercent * 100);

  void onChunkOverlapChanged(double value) {
    _pendingChunkOverlap = value;
    notifyListeners();
  }

  Future<void> onChunkOverlapChangeEnd(double value) async {
    await _ragSettings.setChunkOverlapPercent(value / 100);
    _pendingChunkOverlap = null;
    notifyListeners();
  }
```
Repeat the pattern for semanticWeight, searchTopK, maxHistoryMessages, maxTokens. (Keep the existing `set*` methods or replace their call sites.)

- [ ] **Step 2: Wire the view**

In `settings_view.dart`, each `Slider` gets `onChanged:` → the transient handler and `onChangeEnd:` → the persist handler, and reads its value from the display getter. Example (chunk overlap, `:300-308`):
```dart
                    slider: Slider(
                      value: viewModel.chunkOverlapDisplay,
                      max: 30,
                      divisions: 6,
                      label: '${viewModel.chunkOverlapDisplay.toStringAsFixed(0)}%',
                      onChanged: viewModel.onChunkOverlapChanged,
                      onChangeEnd: viewModel.onChunkOverlapChangeEnd,
                    ),
```
Repeat for the other four sliders.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/ui/views/settings/ && flutter test`
Expected: clean; suite green. Manually drag a slider and confirm one persisted write on release (verification-before-completion).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/views/settings/settings_view.dart lib/ui/views/settings/settings_viewmodel.dart
git commit -m "perf(settings): persist slider values on change-end, not every tick"
```

---

## Task 11: Dependency + platform-privacy batch (M-27, M-29, L-5)

**Shape:** Config/decision. Verification = pub get / analyze / plist inspection.

**Files:**
- Modify: `pubspec.yaml:17` (M-27)
- Modify: `ios/Runner/Info.plist:55-56` + `lib/services/vector_store_path_native.dart:7` (M-29)
- Reference: `macos/Runner/Release.entitlements:7-8` (L-5)

- [ ] **Step 1: Move file_picker off beta (M-27)**

Check pub.dev for the latest **stable** `file_picker`. Update `pubspec.yaml:17` to the stable caret range, run `flutter pub get`, and fix any API changes (the working tree already migrated to `FilePicker.pickFiles`; confirm the stable release exposes that API — if the beta API differs from stable, reconcile). Reconcile with M-19 (`PlatformFile.bytes` deprecation): confirm `.bytes` usage in `document_management_service.dart:126,134` matches the stable API; migrate to the recommended accessor if deprecated.

- [ ] **Step 2: Decide iOS file-sharing exposure (M-29)**

`Info.plist:55-56` sets `UIFileSharingEnabled=true`, exposing the entire document/chat DB (stored under `getApplicationDocumentsDirectory()`, `vector_store_path_native.dart:7`) via Finder/iTunes. Decide with the maintainer: if file sharing is not an intended feature, remove the key (privacy fix) **and/or** move the DB to Application Support. Default (privacy-preserving): remove `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` if present. Record the decision in `docs/web-deployment.md`/a privacy note.

- [ ] **Step 3: Document macOS library-validation entitlement (L-5)**

`Release.entitlements:7-8` sets `disable-library-validation=true` — likely required by flutter_gemma dylibs (sandbox still on). Confirm necessity (try a build without it if feasible); if required, add an XML comment in the entitlements file justifying it. No code change if confirmed necessary.

- [ ] **Step 4: Verify**

Run: `flutter pub get && flutter analyze && flutter test`
Expected: resolves; clean; green.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist macos/Runner/Release.entitlements
git commit -m "chore: stable file_picker; iOS file-sharing privacy decision; document macOS entitlement"
```

---

## Task 12: Logging + crash-reporting + lifecycle batch (L-1, L-2, L-3, L-4) + L-27 runtime request

**Shape:** Config/infra. Verification = analyze + a smoke test that log level gates.

**Files:**
- Modify: `lib/services/logging_service.dart` (level from environment)
- Modify: `lib/services/auth_token_service.dart:38-44` (gate env token behind debug)
- Modify: `lib/bootstrap.dart:48-50` (runZonedGuarded + close DB on lifecycle)

**Why:** L-2 verbose DEBUG + device metadata in production (`adb logcat` readable); L-1 `--dart-define` HF token baked/auto-persisted; L-3 no `runZonedGuarded`/crash reporter; L-4 no lifecycle observer, `VectorStore.close()` has zero callers.

- [ ] **Step 1: Level-aware logging (L-2)**

In `logging_service.dart`, read a minimum level from `kReleaseMode` (or `EnvironmentService`): in release, set the `Logger` `level` to `Level.warning`; in debug, `Level.debug`. Route the `dart:developer log()` calls in `startup_viewmodel.dart` (`:41,127,130,186`) and the 21 `DEBUG:` sites in `model_management_service.dart` through `LoggingService` so they are gated (or wrap them in `if (kDebugMode)`). At minimum, gate the raw `log()` `DEBUG:` calls behind `kDebugMode`.

- [ ] **Step 2: Gate env-var HF token behind debug (L-1)**

In `auth_token_service.dart:38-44`, wrap the `String.fromEnvironment('HUGGINGFACE_TOKEN')` fallback in `if (kDebugMode)` so a `--dart-define` token is never baked into a release binary. Import `package:flutter/foundation.dart`.

- [ ] **Step 3: runZonedGuarded + crash log (L-3)**

In `bootstrap.dart`, wrap `runApp(...)` in `runZonedGuarded`, forwarding zone errors to a persisted error log (or a crash reporter if one is chosen). Keep `FlutterError.onError` but also record to the same sink.

- [ ] **Step 4: Close DB on lifecycle detached (L-4)**

Add an `AppLifecycleListener` (or `WidgetsBindingObserver`) in the app root that calls `locator<VectorStore>().close()` on `AppLifecycleState.detached`, so in-flight batch writes are flushed on process kill. `VectorStore.close()` (`:547-550`) currently has no callers.

- [ ] **Step 5: Request POST_NOTIFICATIONS at runtime (completes L-27)**

Phase 1 Task 1 declared `POST_NOTIFICATIONS` in the manifest; on Android 13+ the download-progress notification (`bootstrap.dart:36-43`) still won't show without a **runtime** request. Since `permission_handler` is not currently a dependency and `background_downloader` may request it itself, first check whether the downloader already prompts. If not, request the permission once at startup on Android 13+ (e.g. via `permission_handler` if adopted, or the downloader's own API). If adding a dependency is undesirable, document that download-progress notifications are best-effort on Android 13+ and the download still completes (foreground service runs regardless). Record the decision in a comment near `bootstrap.dart:36`.

- [ ] **Step 5: Verify**

Run: `flutter analyze && flutter test`
Expected: clean; green.

- [ ] **Step 6: Commit**

```bash
git add lib/services/logging_service.dart lib/services/auth_token_service.dart lib/bootstrap.dart lib/app/main_app.dart
git commit -m "chore(obs): level-gated logging, debug-only env token, runZonedGuarded, close DB on detach"
```

---

## Task 13: UI polish batch (L-7, L-8*, L-9, L-14, L-16, L-17, L-18, L-19, L-20, L-26)

**Shape:** UI/constants. Verification = analyze + targeted widget behavior; batched one-line fixes sharing one review. (*L-8 already applied in Task 5.)

**Files:** as listed per item.

- [ ] **Step 1: L-7 — byte docs can't refresh**

`document_management_service.dart:340-342`: `refreshDocument` throws `FileSystemException('Original file not found')` for byte-ingested docs (whose `filePath` is a filename). Add a `hasSourceFile` notion (e.g. treat `filePath` that isn't an existing file as byte-sourced) and skip/So-graceful-return file-based refresh for byte docs instead of throwing.

- [ ] **Step 2: L-9 — centralize magic numbers**

`vector_store.dart:187,190` (candidate pool 100), `rag_token_manager.dart:38` (history cap 10), `contextual_retrieval_service.dart:49,59-63` (2048, ratios) → add named constants in `RagConstants` and reference them.

- [ ] **Step 3: L-14 — single source for history cap**

`chat_viewmodel.dart:166` hardcodes `.take(10)`; `maxHistoryMessages` is applied downstream (clamped 0–5). Replace `.take(10)` with reading the setting once (via `RagSettingsService`) so there's a single source; the downstream clamp still applies.

- [ ] **Step 4: L-16 — no state mutation in builder**

`chat_view.dart:121-124`: `onScrolled()`/`_scrollToBottom` run inside `builder()`. Move into a post-frame callback: `WidgetsBinding.instance.addPostFrameCallback((_) { if (viewModel.shouldScroll) { _scrollToBottom(viewModel); viewModel.onScrolled(); } });`.

- [ ] **Step 5: L-17 — confirmDismiss returns real result**

`document_library_view.dart:143-146`: `confirmDismiss` calls `deleteDocument` then returns `false`. Change to return the confirmation result so the dismiss animation matches; ensure `deleteDocument` returns a `bool` (confirmed) and `confirmDismiss` returns it.

- [ ] **Step 6: L-18 — clean EPUB HTML**

`document_parser_service.dart:168-173`: `stripHtml` leaves entities and `<script>/<style>` bodies. Strip `<script>…</script>` and `<style>…</style>` first, then tags, then unescape common entities (`&amp; &lt; &gt; &quot; &#39; &nbsp;`).

- [ ] **Step 7: L-19 — trim send + gate Enter while processing**

`chat_input.dart:28,121`: `_handleSend` checks `_controller.text.isEmpty` (no trim) and `onSubmitted` fires while processing. Change to `if (_controller.text.trim().isEmpty || widget.isProcessing) return;` and pass the trimmed text to `onSend`.

- [ ] **Step 8: L-20 — source chip with null documentId**

`chat_viewmodel.dart:223-238`: `showSourceDetail` no-ops when `documentId` is null but the chip looks tappable. Either always show the metadata dialog (it already builds a dialog from `source.content`), by removing the `if (docId != null)` gate so all sources open the dialog, or disable the chip visually when `documentId` is null in the view.

- [ ] **Step 9: L-26 — route strings through AppLocalizations**

l10n is fully wired (`en`+`es`, `generate: true`) but user-facing strings are hardcoded English (`main_app.dart:13`, `document_library_viewmodel.dart:43-45,72-74,86-89`, etc.). Move the user-facing strings into the ARB files and read via `AppLocalizations`. Scope: at minimum `main_app.dart` title and the DocumentLibrary dialog strings; note remaining hardcoded strings as a follow-up if exhaustive l10n is too large for one task.

- [ ] **Step 10: Verify + commit**

Run: `flutter analyze && flutter test`
Expected: clean; green.
```bash
git add lib/ test/
git commit -m "polish(ui): byte-doc refresh, constants, history source, builder side-effects, dismiss result, EPUB cleanup, trim/gate send, source chip, l10n strings"
```

---

## Task 14: Critical-path test coverage (audit Test Coverage section)

**Shape:** Test-only. Verification = new tests green; coverage of the flagged gaps.

**Files:**
- `test/services/rag_service_test.dart` — add expansion path, reranking path, contextual retrieval, `documentIds` filter, empty-results, generation-error cases (currently only one happy path, `:74-122`).
- `test/services/vector_store_test.dart` — replace the empty placeholder `combines scores correctly` (`:102-105`) with real assertions on hybrid merge weighting.
- `test/services/embedding_service_test.dart` (new) — the "no active embedder" failure mode.
- `test/services/rag_settings_service_test.dart` — created in Task 8; extend to cover all getters/setters round-trip.
- `test/services/inference_model_provider_test.dart` — created in Phase 3 Task 11.

- [ ] **Step 1: Fill the empty vector_store merge test**

Replace `test/services/vector_store_test.dart:102-105` with assertions that, given known semantic and keyword lists and a `semanticWeight`, `mergeResults` (it's `@visibleForTesting`, `:507`) produces the expected fused ordering. Use small fixtures with hand-computed RRF scores.

- [ ] **Step 2: Add rag_service branch tests**

Add tests for: expansion enabled (verifies `searchWithExpandedQueries` is called), reranking enabled (verifies rerank + `take(searchTopK)`), `documentIds` filter forwarded, empty search results → "No relevant context found." path, and generation throwing → error surfaced. Use the existing mock helpers.

- [ ] **Step 3: Add embedding_service test**

`test/services/embedding_service_test.dart`: stub `FlutterGemma.getActiveEmbedder` to throw (no active embedder) and assert `generateEmbedding` surfaces a clear error (the real user-hit failure mode).

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: all green; the flagged gaps now covered.

- [ ] **Step 5: Commit**

```bash
git add test/
git commit -m "test: cover rag_service branches, hybrid merge, embedding failure, settings"
```

---

## Phase 4 completion gate

- [ ] All 14 tasks committed.
- [ ] `flutter test` → all green; the empty placeholder test is gone; rag_service/embedding_service/rag_settings_service/inference_model_provider have real coverage.
- [ ] `flutter analyze` → 0 errors, 0 warnings; the two deprecated-`bytes` infos resolved (M-19 via M-27) if the stable file_picker API allows.
- [ ] Manual driver check: ingest a large multi-file corpus, run expansion+rerank queries, confirm no UI stall and correct source ordering.
- [ ] Every audit ID (per master-plan coverage checklist) is now addressed. Run **superpowers:requesting-code-review** before merging the branch.
