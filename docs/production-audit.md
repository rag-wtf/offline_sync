# Production Readiness Audit — offline_sync (Round 2)

**Date:** 2026-08-28
**Branch:** `main` @ `e83b7e3` (clean working tree)
**Scope:** Full codebase — `lib/` (all non-generated Dart), `test/`, Android/iOS/macOS/web platform config, CI workflows.
**Constraint honored:** Audit only. No code modified. Public API unchanged.
**Prior audit:** 2026-07-07 (this file's previous revision). This is a fresh audit of the current state; it verifies which prior findings were fixed and reports new/remaining issues.

## Stack

- **Framework:** Flutter (SDK constraint `>=3.44.0`; CI pins `3.44.x`), Dart `>=3.12`, flavors via `main_development|staging|production.dart`
- **Architecture:** Stacked MVVM + `get_it` locator (`stacked_generator` codegen)
- **Storage:** `sqlite3` v3 (FTS5 + base64 Float64 embeddings, `PRAGMA user_version` = 2) as vector store; `shared_preferences` for settings; `flutter_secure_storage` for the HF token
- **AI:** `flutter_gemma` 1.2.1 — on-device inference + embeddings (Gemma 3 / EmbeddingGemma / Gecko, downloaded from HuggingFace)
- **Domain:** Fully offline on-device RAG (ingest → chunk → embed → hybrid search → optional expansion/rerank/contextualization → generate)

## Verification Status (run 2026-08-28, this machine)

| Check | Result |
|---|---|
| `flutter test --coverage` (full suite) | **339 passed, 0 failed** |
| Line coverage | 3,269 / 3,270 instrumented lines (99.97%; the one uncovered line is a display ternary, `settings_view.dart:379`) — see M-12 for the caveat |
| `flutter analyze` | 0 errors, 0 warnings, 2 infos (`unnecessary_unawaited` — see L-16) |
| Working tree | Clean before and after verification (tool-generated churn reverted) |

Local-run note: on a fresh checkout, `lib/l10n/gen/` is gitignored and tests fail to compile until `flutter gen-l10n` runs (the Flutter tool normally does this implicitly; CI is unaffected). On Windows, `flutter pub get` requires Developer Mode (symlink support).

## Status of the 2026-07-07 audit

The remediation phases landed. Verified fixed against current source (spot-checked, not taken on faith):

- **All 4 Criticals:** `INTERNET` permission in the main manifest (`AndroidManifest.xml:3`); Android release signing fail-closed in CI + `apksigner verify` (`release.yaml:110-159`, `build.gradle.kts:40-62`); semantic scan bounded + base64 embeddings + dimension guard (`vector_store.dart:292-295,658`); DOCX decoded as UTF-8 (`document_parser_service.dart:158-161`).
- **Highs:** timeouts on embedding/rerank/expansion/contextualization; expansion RRF uses per-list rank; retry stream re-subscribe fixed; chat double-submit fixed; stream loop checks `disposed`; PDF disposed in `finally`; token dialog error handling; document-detail try/finally; web attach path; `--build-number/--build-name` on every build; schema versioning (`user_version`=2, UNIQUE `content_hash` + dedup migration); release workflow gated on analyze+test (`verify` job); ingestion listener stored + cancelled; web ships `coi-serviceworker.js` + self-hosted flutter_gemma JS runtime; iOS artifact explicitly labeled UNSIGNED/inspection-only.
- **Mediums/Lows (sample):** rerank score parsing (`\d+(\.\d+)?`), streaming path uses `searchTopK`, budget uses the active model config, in-flight hash guard for duplicate ingestion, `file_picker` on stable 11.x, deps locked via committed `pubspec.lock` (manifest uses caret ranges), secure-storage iOS accessibility set, env-token gated to `kDebugMode`, level-gated logging + crash-log persistence + `runZonedGuarded`, DB closed on lifecycle detach, `Document.fromJson` null-safe, sliders persist on `onChangeEnd`, `POST_NOTIFICATIONS` declared + runtime request, `UIFileSharingEnabled` removed, `ITSAppUsesNonExemptEncryption` set, chat input trims/gates, `confirmDismiss` returns the real result.

**Carried over (still open):** chunk-overlap no-op (now M-3), checksums missing for 7/8 models (M-4), `ModelManagementService.initialize()` unguarded (M-6), Syncfusion license decision (M-11), unclamped settings read path (L-1), 401 substring matching (L-2), statement close on error (L-3), partial l10n (L-11), dead `RagService.ingestDocument` path (L-12).

## Summary

| Severity | Count | Theme |
|---|---|---|
| Critical | 0 | — |
| High | 5 | Stale model cache after switch; no timeout on answer generation; token budget ignores user maxTokens; embedding-model switch silently corrupts retrieval; macOS sandbox blocks network/file access |
| Medium | 14 | Concurrent chats self-destruct on one native model; semantic recall bounds; dormant checksum machinery; chunk-overlap no-op; REPLACE-on-unique-hash hazard; init race; UI/model mismatches; ingestion memory; licensing; coverage-gate accuracy; sessions never released; corpus in backed-up storage |
| Low | 16 | Hygiene: unclamped reads, dead code, ordering ties, partial l10n, CDN dependency, observability gaps |

**Overall verdict: materially release-ready for a controlled/beta release on Android, Windows/Linux desktop, and web; macOS is not shippable until H-5 lands (missing entitlements break both first-run flows); not yet for iOS distribution (unsigned by design).** The July release blockers are fixed and verified. What remains is a small set of correctness bugs that surface through supported Settings interactions (H-1..H-4) plus the macOS entitlement gap (H-5) — none block first install on the ready platforms, all bite real users within normal usage. Recommend fixing the five Highs before shipping v1.0.0.

---

## HIGH

### H-1. Switching the inference model never takes effect — `InferenceModelProvider.clearCache()` has zero callers
- **Files:** `lib/services/inference_model_provider.dart:26-29,69-71`; `lib/services/model_management_service.dart:484-506` (`switchInferenceModel` doesn't touch the provider); `lib/ui/views/settings/settings_viewmodel.dart:128-131`
- `getModel()` returns the memoized `_model` forever once loaded. `switchInferenceModel` re-activates the new model natively and persists the new id, but nothing invalidates the provider cache — `clearCache()` is defined and never called anywhere in `lib/`. All generation (RAG answers, reranking, query expansion) keeps using the old cached handle until app restart. Worse, the token-budget math follows the *new* `activeInferenceModelId` (`rag_service.dart:344-348`), so budgets are computed for a model that isn't the one generating.
- **Production impact:** A user who upgrades from Gemma 270M to 1B sees no quality change and no error; prompts may be budgeted at 2048 tokens into a session created for 1024 → truncation/native failures. Also applies when the user changes the maxTokens setting.
- **Fix:** Call `locator<InferenceModelProvider>().clearCache()` (and dispose the old handle) in `switchInferenceModel` and in `RagSettingsService.setMaxTokens`; memoize the in-flight `Future<InferenceModel>` while at it (see M-6 pattern).

### H-2. No timeout on answer generation — a hung inference permanently disables chat
- **Files:** `lib/services/rag_service.dart:390-395` (`_generate` loop), `:457-462` (`_generateStream` loop); state gate `lib/ui/views/chat/chat_viewmodel.dart:146,229` and `chat_input.dart:29,122-124,140`
- Every helper LLM call has a timeout (embedding 30s, rerank 15s, expansion 15s, contextualization 20s) — but the main answer generation, the one path every query hits, has none. If native inference hangs (observed failure mode on MediaPipe/LiteRT under memory pressure), the `await for` never completes, `_isProcessing` stays `true`, and the send button and Enter key are disabled for the life of the view. (`ChatViewModel` is view-scoped, so navigating away and back does restore the input — but the hung generation keeps running and the next query reuses the same possibly-wedged model handle.)
- **Fix:** Apply an inactivity timeout to the token stream (e.g. `stream.timeout(const Duration(seconds: 30))` — resets per token, so long answers still work); on timeout, surface a recoverable error and reset `_isProcessing`.

### H-3. Token budget ignores the user's maxTokens override — guaranteed overflow when the user lowers it
- **Files:** `lib/services/rag_service.dart:344-351` and `:407-414` (budget from `ModelConfig...maxTokens` only) vs `lib/services/inference_model_provider.dart:34-44` (session created with `settings.maxTokens ?? modelConfig.maxTokens`)
- The inference session is created honoring the user's Settings override, but the prompt budget always uses the model's catalog default. Set maxTokens to 512 on the 2048-token Gemma 1B: the session accepts 512 tokens, the budget happily builds ~1,300-token prompts → every query fails or truncates. (H-1's stale cache makes the mismatch worse in the other direction.)
- **Fix:** One source of truth: `final maxTokens = settings.maxTokens ?? modelConfig.maxTokens;` in both `_generate` and `_generateStream`.

### H-4. Switching the embedding model silently breaks retrieval for all existing documents
- **Files:** `lib/services/model_management_service.dart:509-533` (`switchEmbeddingModel`); `lib/services/vector_store.dart:658-660` (dimension guard)
- Switching embedders re-activates the new model but never re-embeds stored vectors, and vector rows carry no record of which embedder produced them. All four catalog embedding models output the same dimensionality (768 per the models' documentation — the catalog encodes no dimension field; the 64/256/512/1024 in their names are sequence lengths, per the comments at `model_config.dart:112,130,146,162`), so the dimension guard never skips a row: queries embedded in the new vector space are cosine-scored against vectors from the old space. The results are numerically valid and semantically meaningless.
- **Production impact:** Retrieval quality silently collapses after a supported Settings action; the user has no signal and no remedy short of deleting and re-adding every document.
- **Fix:** Store the embedder model id per vector row (metadata or column); filter search to rows matching the active embedder; on switch, warn the user and offer re-indexing.

### H-5. macOS builds are sandboxed with no network or file-access entitlements — model download and document import cannot work
- **Files:** `macos/Runner/Release.entitlements` (only `app-sandbox` + `disable-library-validation`); `macos/Runner/DebugProfile.entitlements` (adds only `allow-jit` + `network.server`); shipped as-is by `release.yaml:340-394`
- Neither entitlements file grants `com.apple.security.network.client`, so every outbound connection — including the HuggingFace model download — is denied by the sandbox; and neither grants `com.apple.security.files.user-selected.read-only`, so paths returned by the file picker can't be read. Both first-run flows (install a model, add a document) are dead on macOS, in debug and release alike — which strongly suggests the macOS app has never been exercised end-to-end.
- **Fix:** Add `com.apple.security.network.client` and `com.apple.security.files.user-selected.read-only` to both entitlements files; then actually run the DMG through first-run before calling macOS a release target.

---

## MEDIUM

### M-1. Concurrent chats on one native model self-destruct — reranking scores collapse to the neutral fallback
- **Files:** `lib/services/reranking_service.dart:27-41` (batches of 5 concurrent `createChat` + `generateChatResponseAsync` on one `InferenceModel`); `lib/services/document_management_service.dart:262-311` (10 concurrent `generateEmbedding`)
- The July fix bounded rerank fan-out to batches of 5 — but this isn't merely "undocumented concurrency": flutter_gemma 1.2.1's own API docs (`flutter_gemma_interface.dart:146-152`) state that `createChat`/`createSession` is a singleton lane where **each call closes the previous session**, and that concurrent dialogues require `openSession`/`openChat`. So within each batch of 5, later `initSession()` calls close the earlier chats' in-flight sessions; their generations fail and are swallowed into the neutral 5.0 fallback (`:36`, `:119`). Net effect: reranking silently orders by mostly-tied neutral scores (and Dart's `sort` is not stable) instead of relevance. The plugin also documents that generation is *serialized* across sessions, so the concurrency buys no latency anyway. The 10-way embedding fan-out targets a different API (the embedder) whose concurrent-call safety remains unverified; embedding failures abort ingestion.
- **Fix:** Use `openChat` (built for concurrent chats on one model) or score at concurrency 1 — the plugin serializes generation regardless; measure whether >1 concurrent embedding call actually helps.

### M-2. Semantic recall is bounded by keyword candidates — pure-semantic matches unreachable at scale
- **File:** `lib/services/vector_store.dart:249-256` (candidate pre-filter), `:292-297` (`LIMIT` without `ORDER BY`)
- The C-3 fix works by restricting semantic scoring to the FTS keyword candidates (pool 100). Consequence: a chunk that matches only semantically (paraphrase, synonym, cross-lingual) can never be retrieved once the corpus outgrows the fallback scan. When FTS returns nothing, the fallback scans `LIMIT 500` **without ORDER BY** — an arbitrary subset of the table, so results beyond ~500 chunks are nondeterministic.
- **Production impact:** Fine for small libraries (≤500 chunks scans everything). Beyond that, "hybrid" search quietly degrades to keyword-gated search. This is an accepted trade-off, but it is undocumented and the no-candidate path is arbitrary rather than principled.
- **Fix (incremental):** add `ORDER BY created_at DESC` (recency) or rowid to make the fallback deterministic; document the recall bound; longer-term, batch-scan all rows in the isolate or adopt an ANN index.

### M-3. Chunk-overlap setting is still a no-op; the settings-driven chunking path is still dead code *(carried, M-25)*
- **Files:** `lib/services/smart_chunker.dart:20` (hardcoded `overlapChars = 50`); `lib/services/document_management_service.dart:456-478` (`_parseAndChunk` calls `chunker.chunk(...)` with defaults); `lib/services/rag_service.dart:304-336` (`ingestDocument`/`splitIntoChunks` — the only consumer of `chunkOverlapPercent`, unreachable from any production path); slider UI `settings_view.dart:300-311`
- The Settings "chunk overlap" slider persists a value nothing reads on the live path. Note the parse/chunk step runs in a `compute` isolate, so the fix must pass the overlap value in `parseParams` (the isolate can't use the locator).
- **Fix:** Thread `settingsService.chunkOverlapPercent` through `parseParams` into `SmartChunker.chunk`; delete `RagService.ingestDocument`/`splitIntoChunks`.

### M-4. Checksum verification is live for 1 of 8 models — dormant for every inference model
- **File:** `lib/services/model_config.dart:114` (only `gecko64` has `sha256`); enforcement `lib/services/model_management_service.dart:564-604`
- The fail-closed verification machinery from M-1 (July) is implemented and tested, but 7 of 8 catalog models — including all four inference binaries (300MB–6.5GB, two hosted in `*-litert-preview` repos that can be force-pushed) — carry no digest, so they install with zero integrity checking.
- **Fix:** Populate `sha256` for all 8 models (HF exposes digests via Git LFS pointers); consider failing CI if a catalog entry lacks one.

### M-5. `INSERT OR REPLACE` + UNIQUE(content_hash) silently destroys document rows; refresh failure orphans vectors
- **Files:** `lib/services/vector_store.dart:479-502` (`insertDocument` uses `INSERT OR REPLACE`), `:213-217` (v2 migration adds UNIQUE index on `content_hash`); `lib/services/document_management_service.dart:364-380` (`refreshDocument`), `:203` (processing row inserted at ingestion start)
- SQLite's REPLACE resolves *any* uniqueness conflict — including the new UNIQUE hash index — by deleting the conflicting row. `refreshDocument` on an unchanged file inserts a new `processing` row with the same hash, which evicts the old document row *before* ingestion succeeds. If parsing/embedding then fails, the original document record is gone and its vectors are orphaned (still searchable, no owning document). Mitigating factor: `refreshDocument` currently has no UI caller (see L-12) — but the landmine arms the moment anyone wires it up, and `INSERT OR REPLACE` semantics on a table with a UNIQUE index are easy to trip in future code.
- **Fix:** Use explicit `ON CONFLICT(id) DO UPDATE`-style upserts (or plain INSERT + UPDATE); in refresh, only delete the old row after the new ingestion succeeds.

### M-6. `ModelManagementService.initialize()` has no idempotency/concurrency guard *(carried, M-28)*
- **Files:** `lib/services/model_management_service.dart:135-218`; `lib/ui/views/settings/settings_viewmodel.dart:107` (`unawaited(_modelService.initialize())` on every Settings visit); `startup_viewmodel.dart:145` (awaited during startup)
- Every navigation to Settings re-runs full init — re-checking installs, re-hashing the gecko model (see L-4), re-activating both models natively — potentially concurrent with startup init or an in-flight download. `_models` status flags are mutated from overlapping runs.
- **Fix:** Memoize an in-flight/completed `Future<void>` and return it; add an explicit `refresh()` for the cases that truly need re-scanning.

### M-7. Settings maxTokens UI is keyed to the first catalog model, not the active one
- **File:** `lib/ui/views/settings/settings_viewmodel.dart:67-78` (`maxTokens`), `:81-88` (`modelDefaultMaxTokens`), `:226-239` (override cleared when slider == wrong default)
- `firstWhere((m) => m.type == inference)` always resolves to Gemma 270M (1024). With any other model active, the displayed default is wrong, and `onMaxTokensChangeEnd` clears the user's override whenever the slider lands on 1024 rather than the active model's real default. `RagService` was fixed to use `ModelConfig.activeInferenceModelOrDefault` — this UI wasn't.
- **Fix:** Use `ModelConfig.activeInferenceModelOrDefault(_ragSettings.activeInferenceModelId)` in both getters.

### M-8. Document detail shows chunks in random order
- **File:** `lib/services/vector_store.dart:530-534` (`ORDER BY id ASC`); ids are UUIDv4 (`document_management_service.dart:303`); consumer `document_detail_view.dart:72`
- Chunk ids are random UUIDs, so `ORDER BY id` is a shuffle. The sequence number exists in `metadata.seq` but isn't used. Users inspecting a document see its chunks out of reading order.
- **Fix:** `ORDER BY CAST(json_extract(metadata, '$.seq') AS INTEGER)` or sort in Dart on `metadata['seq']`.

### M-9. Prompts embed Gemma turn markers inside the chat API — likely double templating
- **Files:** `lib/services/rag_service.dart:365-377,428-440`; `lib/services/contextual_retrieval_service.dart:81-96`
- The prompt strings hand-roll `<start_of_turn>user ... <end_of_turn><start_of_turn>model` and are then passed through `chat.addQuery(Message(...))` + `generateChatResponseAsync()`, which apply flutter_gemma's own chat templating. If the plugin templates (it does for `gemmaIt` model type), the model sees nested turn markers — a known cause of degraded answers and control-token leakage. Reranking and expansion prompts (no markers) are the correct pattern.
- **Fix:** Verify flutter_gemma 1.2.1's templating for `ModelType.gemmaIt`; if it templates, strip the manual markers.

### M-10. Ingestion holds the whole document pipeline in memory at once *(carried, reduced)*
- **File:** `lib/services/document_management_service.dart:213-318`
- Peak memory ≈ full text + all chunks + (if contextual retrieval) contextualized copies + **all** embedding vectors (768 × 8 bytes each), inserted in one batch at the end. Parsing correctly runs in an isolate, but embedding accumulation runs on the main isolate. The max-document setting defaults to 10MB and clamps at 50MB (`rag_settings_service.dart:131,144` — no UI exposes the setter today); toward the ceiling, low-RAM devices can still OOM.
- **Fix:** Call `insertEmbeddingsBatch` per 10-chunk batch instead of accumulating `embeddingDataList`; drop `content` reference after chunking when contextual retrieval is off.

### M-11. Syncfusion commercial license still unregistered/undocumented *(carried, M-26 — legal, not code)*
- **Files:** `pubspec.yaml` (`syncfusion_flutter_pdf: ^33.2.13`); repo-wide grep for `registerLicense`: 0 hits
- Nothing fails at runtime (the PDF package doesn't enforce), but distribution without a Community License eligibility check or commercial license is a legal exposure. `docs/licensing.md` exists and correctly frames the options — but records the decision as still pending ("Maintainer decision required").
- **Fix:** Confirm Community License eligibility (revenue/headcount caps) or purchase; complete the pending decision in `docs/licensing.md`.

### M-12. "100% coverage" is 100% of *instrumented* lines — 76 ignore regions exclude critical branches
- **Files:** 139 `coverage:ignore*` markers across `lib/` (63 start/end pairs + 10 single-line + 3 whole-file = 76 regions; heaviest: `model_management_service.dart` 35, `document_management_service.dart` 27, `rag_service.dart` 18 — e.g. `vector_store.dart` FTS branch selection, `rag_service.dart` search-path branches, all native `FlutterGemma.*` call sites, web-only paths); CI gate `main.yaml:24` (`min_coverage: 100`)
- The gate is real and valuable, but the headline number overstates what's tested: the hybrid-search branch choice, download/activation flows against the real plugin, and web code paths are structurally excluded. That's a reasonable unit-test boundary — the risk is treating the badge as evidence those paths work. Note the defects in M-8 and M-10 sit *inside* ignore regions (`document_management_service.dart:289-292`, `:269-273`), which is precisely how they survived a 100% gate.
- **Fix:** No code change required. Track ignored regions (fail CI if the count grows), and cover the native-boundary flows with a small integration/e2e suite on a device farm before major releases.

### M-13. Native inference model and chat sessions are never released — KV-cache memory stays resident in background
- **Files:** `lib/services/inference_model_provider.dart` (process-lifetime `_model` cache; see H-1); no `chat.close()`/session close anywhere in `lib/` (repo grep: only sqlite and stream-controller closes); `lib/app/main_app.dart:39-53` releases only the `VectorStore` on detach
- Every generation path creates chats via `createChat` and abandons them; the singleton-lane semantics (M-1) close the *previous* session, so exactly one session — with its KV cache, ~100–500MB per the plugin's docs depending on model and maxTokens — stays resident indefinitely, including while the app is backgrounded. On mobile that's a direct invitation for OS OOM-kills of the backgrounded app.
- **Fix:** Close the active chat/session after generation completes (or on lifecycle pause), and dispose the cached model in the same place H-1's `clearCache()` call lands.

### M-14. The entire corpus and chat history live in `Documents/` — included in iCloud/device backups on Apple platforms
- **Files:** `lib/services/vector_store_path_native.dart:6-9` (`getApplicationDocumentsDirectory()`); `vectors.db` holds full chunk text, the document inventory, and the complete chat history (`vector_store.dart:114-163`), unencrypted
- On iOS/macOS, `Documents/` is backed up to iCloud/Finder by default and (on iOS) user-visible in the Files app. A product whose stated premise is that no data leaves the device ships its whole knowledge base off-device on the first backup. Apple's guidance puts app-managed databases in `Application Support`. (Android's `allowBackup` posture should be checked in the same pass.)
- **Fix:** Move the DB to `getApplicationSupportDirectory()` with a one-time file migration (and/or set `NSURLIsExcludedFromBackupKey`); document the backup posture either way.

---

## LOW

| # | File:Line | Issue | Fix |
|---|---|---|---|
| L-1 | `rag_settings_service.dart:44-58` | Persisted settings load unclamped (setters clamp on write only); prefs from an older/tampered build bypass every clamp — e.g. `semanticWeight > 1` inverts keyword weighting (`vector_store.dart:609`) *(carried)* | Clamp in `initialize()` |
| L-2 | `model_management_service.dart:450-455`; `startup_viewmodel.dart:79-84,99` | Auth flow still inferred from `contains('401')` though `AuthenticationRequiredException` exists *(carried)* | Throw/propagate the typed exception |
| L-3 | `vector_store.dart:428-441,480-501` (`..execute()..close()` cascades), `:450-474` (batch catch at `:471-474` skips `stmt.close()`) | Prepared statements leak when `execute` throws *(carried, partial)* | `try/finally` around close (as `chat_repository.dart:33-69` already does) |
| L-4 | `model_management_service.dart:175-183` | Startup SHA-256-hashes the 110MB gecko file on every launch (only model with a digest); grows to GBs if M-4 is fixed naively | Cache verification result (path+mtime+size) |
| L-5 | `chat_viewmodel.dart:173-181` | Conversation history includes the message being asked — the current question appears twice in the prompt, wasting budget | Skip 2 (placeholder + current user msg) |
| L-6 | `bootstrap.dart:33` vs `:105` | `ensureInitialized()` runs outside `runZonedGuarded` — framework callbacks bind to the root zone, so the zone guard misses most async errors (Flutter warns "Zone mismatch" in debug) | Use `PlatformDispatcher.instance.onError` instead of the zone |
| L-7 | `logging_service.dart:69-87` | Crash logs persist to SharedPreferences (max 50) but nothing reads, surfaces, or exports them — observability dead-ends on the device | Add a debug-screen viewer or share/export action |
| L-8 | `chat_repository.dart:74-80` | `ORDER BY timestamp` with ms resolution — user+AI messages written in the same ms can swap on reload | `ORDER BY timestamp, id` |
| L-9 | `vector_store.dart:171-189,428-441` | `INSERT OR REPLACE` into `vectors` doesn't fire the FTS `BEFORE DELETE` trigger on conflict eviction (SQLite: delete triggers skip REPLACE unless `recursive_triggers` on) → stale external-content FTS rows. Ghost rows are filtered by the JOIN; harm is index bloat/skewed bm25. Rare path today (fresh UUIDs) | `PRAGMA recursive_triggers = ON` at init, or explicit delete-then-insert |
| L-10 | `document_library_viewmodel.dart:123-128` | `setBusy(true)` … `setBusy(false)` around delete without try/finally — a throw leaves the library busy forever | try/finally |
| L-11 | `settings_view.dart` (~35 sites — the file has no l10n import at all), `document_library_view.dart:31,38,49`, `startup_view.dart:225,232`, `token_input_dialog.dart` (9 sites — the whole dialog) | l10n applied to the chat flow but ~50 user-facing strings remain hardcoded English — Spanish locale still half-translated *(carried, partial)* | Route through `AppLocalizations` |
| L-12 | `embedding_codec.dart` (unused — `vector_store.dart:638-645` duplicates it inline, with better legacy handling); `rag_service.dart:304-336,470-561` (dead, see M-3); `model_management_service.dart:536-542` (`switchModel` is an empty stub); `document_management_service.dart:364-411,421-423` (`refreshDocument`/`hasDocumentChanged`/`optimizeDatabase` have no UI callers) | Dead code misleads maintainers and hides bugs (M-5 lives in a dead path) | Delete or wire up deliberately |
| L-13 | `web/index.html:43-47` | `@mediapipe/tasks-genai@0.10.27` imported from jsDelivr at runtime — module imports can't carry SRI; a CDN outage or compromise breaks/hijacks web inference (everything else is now self-hosted) | Self-host the package like `litert_embeddings.js` |
| L-14 | `vector_store.dart:437,461-463` | Embeddings stored as Float64 (6KB per 768-dim chunk); Float32 halves DB size and I/O with no retrieval-quality loss | Store `Float32List` (with decode fallback) |
| L-15 | `rag_service.dart:349-357` (duplicated verbatim at `:411-420` — the streaming path the chat UI actually uses) | `availableForPrompt` can go negative on a very long question → context/history budgets negative → silent "No relevant context found." | Clamp to 0 and log — in both copies |
| L-16 | `chat_view.dart:17`, `chat_message_tile.dart:155` | 2 analyzer infos: `unnecessary_unawaited` | Remove the wrappers |

---

## Error handling & input validation — assessment

Broadly solid now: every UI-triggered async path has try/catch with user feedback; ingestion failures persist an error-status document; helper LLM calls have timeouts with graceful degradation (rerank → original order, expansion → original query, contextualization → plain chunk, all logged); FTS input sanitized; file size limits enforced on both ingestion paths; binary-file detection for unknown extensions; token dialog validates format. Remaining gaps are H-2 (generation timeout), L-10, and L-15.

## Logging & observability — assessment

`LoggingService` is level-gated (`warning`+ in release), crash handlers are installed (`FlutterError.onError`, zone guard — see L-6), and crashes persist locally (L-7: nothing reads them). This is a reasonable posture for a privacy-first offline app — no telemetry by design — but recognize the consequence: production failures are invisible unless a user sends you their device. The crash-log export (L-7) is the cheapest way to close that loop. Note `dart:developer log()` calls throughout services (`model_management_service`, `startup_viewmodel`, `device_capability_service`) bypass the level gate, but `log()` is a no-op in release AOT builds, so nothing leaks.

## Configuration management — assessment

No hardcoded secrets anywhere (re-verified: `lib/`, platform dirs, CI). HF token: secure storage with iOS `first_unlock` accessibility, legacy migration deletes the unencrypted copy, env-var fallback is debug-only. Model URLs are HTTPS-only catalog constants. Tunables centralized in `RagConstants`/`RagSettingsService`. Flavors wired (dev/staging/prod) though `EnvironmentService` currently gates nothing meaningful — acceptable. CI signing via GitHub Secrets, fail-closed. Remaining: L-1 (unclamped reads).

## Test coverage — assessment

339 tests, 0 failures, 99.97% of instrumented lines; the July gaps (chat_viewmodel, rag_service branches, hybrid merge, settings/library/detail viewmodels, embedding failure modes) now have substantive tests, and CI gates at 100%. The honest caveat is M-12: native-plugin boundaries, web paths, and some branch selections sit behind 76 `coverage:ignore` regions (139 markers), and there is no on-device integration suite. The specific behaviors most in need of a device test are exactly the open Highs: model switch (H-1), hung generation (H-2), embedder switch (H-4), and macOS first-run (H-5) — none of which unit tests can catch, which is how they survived a 100%-coverage gate.

## Performance — assessment

July's pathologies are fixed (bounded scans, batched inserts, isolate parsing, streamed hashing, slider persistence on change-end, pre-compiled regexes). Remaining risks, in order: M-1 (native concurrency), M-10 (ingestion memory), M-2 (recall vs. scale trade-off), L-4 (startup hashing), L-14 (2× embedding storage). Reranking cost is bounded (topK ≤ 20, 500-char truncation, 15s timeouts) but still ~10 LLM generations per query when enabled — it's off by default, which is the right default.

## Deployment readiness — assessment

- **Android: ready.** INTERNET + POST_NOTIFICATIONS declared; signing fail-closed with post-build `apksigner verify`; R8 + proguard rules; monotonic `versionCode` from run number; flavors correct.
- **iOS: intentionally not distributable.** `--no-codesign`, artifact labeled UNSIGNED-inspection-only with a workflow warning. Fine as a documented decision; needs Apple signing secrets before any TestFlight/App Store plan.
- **Web: ready with caveats.** `coi-serviceworker` shim for SAB; sqlite3 WASM + IndexedDB VFS; self-hosted gemma runtime; caveat L-13 (MediaPipe from CDN) and the shim's known limitation (fails in private windows/older Safari — no in-app messaging for that).
- **Desktop:** Linux AppImage+tarball with artifact verification, Windows zip — both ready. **macOS: not ready** — the DMG builds (with a fail-loud LiteRT JAR step, and `disable-library-validation` documented per July L-5), but the sandbox entitlements block network and picked-file access (H-5), so model download and document import fail in the shipped app.
- **CI:** release gated on analyze+test (`verify` job); main gated on 100% coverage + spell-check; Flutter pinned consistently (3.44.x); Dependabot on.
- **Data migrations:** `PRAGMA user_version` versioning in place (v2 shipped with a real dedup migration — the pattern works). Chat/vector data survives upgrades; M-5 is the one integrity hazard.
- **Health checks / Dockerfile / graceful shutdown:** N/A (client-only app, no server); DB is closed on lifecycle detach.

## Positive findings (verified, no action)

- SQL injection clean: parameterized statements throughout, `IN (...)` via generated placeholders, FTS queries sanitized before `MATCH ?`, LIKE wildcards stripped in fallback search.
- No secrets in repo or CI; keystore material only via Secrets; token never logged.
- Duplicate ingestion defense-in-depth: SHA-256 dedup + in-flight hash set + DB UNIQUE index (+ migration that dedups existing data).
- Transactions with rollback on batch insert/delete; cosine division-by-zero and embedding-dimension mismatches guarded.
- Checksum verification fails closed (deletes the file, marks error) where digests exist.
- Web/native split handled via conditional imports consistently (sqlite, paths, bootstrap).
- The July audit's remediation was genuinely completed, not checkbox-completed — several fixes (signing verification step, fail-loud macOS JAR step, notification best-effort flow) go beyond what was asked.

## Suggested remediation order

1. **Before tagging v1.0.0 (hours):** H-2 (generation timeout — one-line stream timeout + error reset), H-3 (budget source of truth), H-1 (clearCache on switch), H-5 (two entitlement keys + a macOS first-run smoke test — or drop macOS from the release), M-7 (settings display, same root cause as H-3).
2. **Before or immediately after first release (day):** H-4 (embedder tagging + re-index warning — schema v3, easiest before data spreads), M-4 (populate checksums), M-11 (Syncfusion decision — legal), M-1 (switch rerank scoring to `openChat` or concurrency 1 — the plugin docs already settle the question).
3. **Next iteration:** M-3 (wire overlap through the isolate, delete dead path), M-5 (upsert semantics), M-6 (init guard), M-8 (chunk order), M-9 (verify templating), M-10 (incremental inserts), M-13 (session/model disposal), M-14 (move DB out of Documents — a file migration, easiest before data spreads).
4. **Hygiene batch:** the Low table; L-4/L-13 first if M-4/web-hardening land.

*Generated by production audit 2026-08-28 against `main` @ `e83b7e3`. Full test suite and analyzer were run as part of verification; no code was modified.*

*Revised 2026-08-28 after an independent verification pass: every finding was re-checked against source (none falsified; line references corrected where drifted), the test/analyzer/coverage numbers were reproduced, a web release build was confirmed to compile, and three findings were added from the completeness sweep (H-5, M-13, M-14). M-1 was rewritten — flutter_gemma's own API docs settle the concurrency question the original finding left open.*
