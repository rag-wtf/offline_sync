# Production Readiness Audit — offline_sync

**Date:** 2026-07-07 (revised same day after adversarial verification — see [Verification](#verification))
**Branch:** `no-sync` (uncommitted changes present in working tree)
**Scope:** Full codebase — `lib/` (54 Dart files), `test/` (17 files), Android/iOS/macOS/web platform config, CI workflows, scripts.
**Constraint honored:** Audit only. No code modified. Public API unchanged.

## Stack

- **Framework:** Flutter ^3.35 / Dart ^3.9, flavors via `main_development|staging|production.dart`
- **Architecture:** Stacked MVVM + `get_it` service locator (`stacked_generator` codegen)
- **Storage:** `sqlite3` (FTS5 + JSON-encoded embeddings) as vector store; `shared_preferences` for settings; `flutter_secure_storage` for HF token
- **AI:** `flutter_gemma` 1.2.1 — on-device inference + embeddings (models downloaded from HuggingFace)
- **Domain:** Fully offline, on-device RAG (document ingestion → chunk → embed → hybrid search → rerank → generate)

## Verification Status

| Check | Result |
|---|---|
| `flutter test` (full suite, run 2026-07-07) | **124 passed, 0 failed** |
| `flutter analyze` | 0 errors, 0 warnings, 8 infos (2 relevant: deprecated `PlatformFile.bytes`, see M-19) |
| Stale `test_output.txt` at repo root | Shows 1 failure from an old run (pre-refactor); superseded by today's green run. Safe to delete. |

## Summary

| Severity | Count | Theme |
|---|---|---|
| Critical | 4 | Release APK cannot download models; unsigned Android artifacts; O(n) full-table vector scan; DOCX text corruption |
| High | 17 | No inference timeouts; serial per-chunk LLM calls; RRF ranking bug; UI races and listener leaks; iOS artifact unsigned; web release channel likely broken; no versionCode bump; no DB migration path; no CI test gate |
| Medium | 27 | Checksum-less model downloads; error-handling gaps; memory-scaling ingestion; dead chunking path (settings no-op); Syncfusion licensing; beta dependency |
| Low | 27 | Logging hygiene; unpinned deps; unclamped settings read path; iOS metadata gaps; UX inconsistencies |

Overall verdict: **not release-ready.** C-1 and C-2 alone make the Android release build non-functional/un-publishable; the iOS and web release channels have analogous blockers (H-16, H-17). The RAG core is functionally solid (parameterized SQL throughout, good transaction usage, real test suite) but has scalability and robustness gaps that will surface under real-world corpora and flaky devices.

---

## CRITICAL

### C-1. Release Android build has no `INTERNET` permission
- **File:** `android/app/src/main/AndroidManifest.xml`
- `INTERNET` is declared only in `src/debug/AndroidManifest.xml:6` and `src/profile/AndroidManifest.xml:6` (Flutter dev overlays, excluded from release). The main manifest declares only `RUN_USER_INITIATED_JOBS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`.
- **Manifest-merger check (exhaustive):** all 66 `AndroidManifest.xml` files in the pub cache were inspected — every `INTERNET` declaration is in an `example/` app or debug/profile overlay. No dependency plugin *library* manifest (`flutter_gemma` 1.2.1, `background_downloader` 9.5.5, `url_launcher_android`, `device_info_plus`, `file_picker`, `flutter_secure_storage`, …) declares any `uses-permission`. The merger will NOT add it.
- **Production impact:** Release APK/AAB cannot make any network call → model download (the app's mandatory first-run flow) fails for every production user. Invisible in debug/profile testing.
- **Fix:** Add `<uses-permission android:name="android.permission.INTERNET"/>` to `src/main/AndroidManifest.xml`.

### C-2. Release Android artifacts are unsigned
- **Files:** `.github/workflows/release.yaml:52-93`, `android/app/build.gradle.kts:41-56`
- Release signing config reads `ANDROID_KEYSTORE_*` env vars, falling back to `key.properties` (loaded only `if (keystorePropertiesFile.exists())`, `build.gradle.kts:10-14`). The CI `build-android` job sets neither (no keystore secrets; `key.properties` gitignored and absent) → all signing fields resolve null → AGP produces an **unsigned** artifact (it does not fail the build, and it is not debug-signed). No post-build signing/verification step exists.
- **Production impact:** Artifact uninstallable on devices and rejected by Play Store.
- **Fix:** Inject keystore via GitHub Secrets (`ANDROID_KEYSTORE_PATH/ALIAS/PASSWORD/PRIVATE_KEY_PASSWORD`) in the workflow; add a post-build signature verification step (`apksigner verify`).

### C-3. Semantic search loads the entire vector table into memory on every query
- **File:** `lib/services/vector_store.dart:215` (`_semanticSearchAsync`); scoring `:554-579`; isolate hand-off at `:238`
- `SELECT id, content, embedding, metadata FROM vectors` has no `LIMIT`; `limit` is applied only after scoring. Every default (full-library) query reads all rows, JSON-decodes every embedding, and serializes the full dataset to a `compute` isolate (on web, runs on the main thread). The optional `documentIds` filter (`:218-221`) scopes the scan only when the user selects specific documents. Query expansion (when enabled via settings, `rag_service.dart:120,134-136,232`) multiplies this: 3 variants → 3 full scans per user question (`query_expansion_service.dart:76-85`).
- **Production impact:** Latency and memory grow linearly with corpus size; large libraries will stall the UI or OOM on the low-end devices this app targets.
- **Fix:** Restrict the semantic scan to FTS candidate ids (hybrid pre-filter) or add an ANN index; store embeddings as `Float32List` BLOBs instead of JSON text; cap rows scanned.

### C-4. DOCX parsed with wrong encoding — non-ASCII text corrupted
- **File:** `lib/services/document_parser_service.dart:137`
- `String.fromCharCodes(documentEntry.content as List<int>)` treats UTF-8 bytes as raw code units. DOCX `document.xml` is UTF-8; `XmlDocument.parse` (`:138`) receives the already-mis-decoded string and does not re-decode. Accented/CJK/emoji/smart-quote content is mangled before chunking and embedding.
- **Production impact:** Silently corrupted content and degraded retrieval for every non-English DOCX. No error is raised; users just get bad answers.
- **Fix:** `utf8.decode(documentEntry.content as List<int>, allowMalformed: true)`.

---

## HIGH

### H-1. No timeout on any model/inference call
- **Files:** `lib/services/rag_service.dart:383,454`; `reranking_service.dart:86`; `query_expansion_service.dart:36`; `contextual_retrieval_service.dart:97`; `embedding_service.dart:14`
- All on-device LLM/embedding calls (`await for` streams and futures) run unbounded. A hung native inference blocks the request forever with no cancellation path.
- **Fix:** Wrap with configurable `.timeout(...)`; surface a recoverable, user-facing error.

### H-2. Reranking issues N sequential LLM generations per query
- **File:** `lib/services/reranking_service.dart:26-34`
- One full model generation per candidate, serially — `rerankTopK` extra generations added to every query's latency on-device.
- **Fix:** Batch candidates into a single scoring prompt, or bound concurrency and add timeouts.

### H-3. Contextual retrieval: N serial LLM calls + O(n·m) window search per document
- **File:** `lib/services/contextual_retrieval_service.dart:120-142`; `_getRelevantWindow` at `:148`
- One model call per chunk (serial, no timeout); `fullDoc.indexOf(chunk)` per chunk is O(chunks × docLen). Ingesting one large document can take minutes with no cancel.
- **Fix:** Record chunk offsets during chunking instead of `indexOf`; add a concurrency limit and per-call timeout.

### H-4. Query-expansion RRF uses concatenation index, not per-list rank
- **File:** `lib/services/query_expansion_service.dart:102-104` (list built by `addAll` per variant at `:85`)
- RRF score `1.0/(k + i + 1)` uses the global index `i` into the concatenated results, so all results from the first variant systematically outrank later variants regardless of intra-list rank. Retrieval-quality bug at the heart of the expansion feature. (Note: `VectorStore.mergeResults` at `vector_store.dart:508-545` implements RRF *correctly* with per-list ranks — the bug is only in the expansion service.)
- **Fix:** Compute RRF from each result's rank within its own variant list.

### H-5. `retry()` re-subscribes to model status stream without cancelling
- **File:** `lib/ui/views/startup/startup_viewmodel.dart:233-251` → `runStartupLogic()` at `:44`
- Each retry re-assigns `_subscription = _modelService.modelStatusStream.listen(...)` without cancelling the previous one; the stream is broadcast (`model_management_service.dart:51`) so the second listen duplicates instead of throwing. `dispose()` (`:263`) cancels only the last subscription.
- **Fix:** Cancel `_subscription` before re-subscribing.

### H-6. Double-submit race in chat `sendMessage`
- **File:** `lib/ui/views/chat/chat_viewmodel.dart:136-148`
- `_isProcessing` guard (`:136`) and `_isProcessing = true` (`:148`) are separated by `await saveMessage` (`:144`). Two rapid taps both pass the guard → duplicate user messages, two concurrent RAG streams writing to shared `messages` state.
- **Fix:** Set `_isProcessing = true` synchronously right after the guard, before any `await`.

### H-7. RAG streaming loop has no dispose/cancel guard
- **File:** `lib/ui/views/chat/chat_viewmodel.dart:176-203` (`dispose()` at `:311-315` cancels only `_progressSubscription`)
- `await for` over `askWithRAGStream` is not held as a cancellable subscription and checks no disposed flag. Navigating away mid-stream leaves on-device inference running, keeps mutating `messages`, and persists via `saveMessage` (`:201`) after teardown. (The per-token `notifyListeners()` itself is harmless — Stacked's `BaseViewModel` no-ops it after dispose — the harm is the wasted inference, post-dispose state mutation, and late persistence.)
- **Fix:** Track disposal (or hold a cancellable subscription); break the loop on dispose.

### H-8. `PdfDocument` not disposed on parse failure
- **File:** `lib/services/document_parser_service.dart:116-124`
- `document.dispose()` (`:120`) only runs on success; the catch (`:122`) rethrows without disposing. (`syncfusion_flutter_pdf` is pure Dart, so this is retained Dart memory rather than a native handle — still a real leak per failed/corrupt PDF until GC, and a missing-try/finally defect.)
- **Fix:** `try/finally` with dispose in `finally`.

### H-9. Token dialog: save failure leaves button permanently disabled
- **File:** `lib/ui/dialogs/token_input_dialog.dart:48-51,115`
- `AuthTokenService.saveToken` not wrapped; on keystore/storage failure `_isSaving` (set `:48`) never resets, button (`onPressed: _isSaving ? null : _saveToken`, `:115`) stays disabled, no error shows. Dead-end auth flow.
- **Fix:** try/catch, reset `_isSaving`, surface `_errorMessage`.

### H-10. Document detail: error during chunk load → permanent spinner
- **File:** `lib/ui/views/document_detail/document_detail_viewmodel.dart:17-22`
- `setBusy(true)` … `setBusy(false)` with no try/finally, no error state. Any throw leaves "Loading chunks..." forever.
- **Fix:** try/catch/finally + error state.

### H-11. Chat file attach silently broken on web
- **File:** `lib/ui/views/chat/chat_viewmodel.dart:251-268`
- Filters `f.path != null` (`:262-264`) and re-reads from disk; on web `path` is always null → `paths` empty → silent return (`:266`). Ignores `file.bytes`, unlike DocumentLibrary's correct `addDocumentFromPlatformFile` flow.
- **Fix:** Delegate to `addDocumentFromPlatformFile(file)` per file.

### H-12. Release versioning never increments
- **Files:** `.github/workflows/release.yaml:39-49`; `pubspec.yaml:3`
- The workflow `version` input feeds only `VERSION_SUFFIX` (artifact filenames); none of the seven `flutter build` invocations (apk `:76`, appbundle `:80`, ios `:113`, linux `:154`, macos `:265`, windows `:296`, web `:333`) passes `--build-number`/`--build-name`. `versionCode` is permanently `1` → Play Store rejects every upload after the first; same for `CFBundleVersion` on iOS.
- **Fix:** Pass `--build-number`/`--build-name` (from the version input or run number) to every `flutter build`.

### H-13. No database schema versioning / migration strategy
- **File:** `lib/services/vector_store.dart:90-170`
- Schema created via `CREATE TABLE IF NOT EXISTS` only; no `PRAGMA user_version`, no upgrade path anywhere in `lib/` (repo-wide grep confirmed; the only "migration" is the unrelated token migration in `auth_token_service.dart`). Any future schema change silently no-ops on existing installs → `no such column` crashes on upgrade with no forward path.
- **Fix:** Adopt `PRAGMA user_version` with gated, versioned migration steps before first release (v1 schema must be stamped now, or upgrades can never be detected).

### H-14. Release workflow runs no tests or analysis
- **File:** `.github/workflows/release.yaml` (355 lines, no analyze/test step in any job)
- Builds and uploads artifacts without `flutter analyze`/`flutter test`; those run only via `main.yaml:19-22` (very_good_workflows) on push/PR to `main`. A `workflow_dispatch` release bypasses them entirely.
- **Fix:** Add an analyze+test job as `needs:` prerequisite for all build jobs.

### H-15. Ingestion progress listener never cancelled → accumulating leak, dead viewmodels keep acting *(downgraded from Critical after verification)*
- **File:** `lib/ui/views/document_library/document_library_viewmodel.dart:30` (mutation `:39`, dialog/refresh `:38-52`)
- `ingestionProgressStream.listen(...)` subscription is never stored; no `dispose()` override exists; the stream is broadcast (`document_management_service.dart:62`) so listeners accumulate on every navigation to DocumentLibraryView. Disposed viewmodels keep receiving events, mutating `_activeIngestions`, firing the 2-second `Future.delayed` continuation, and — worse — each stacked listener triggers its own error dialog / `_refreshDocuments`, so after N visits one ingestion event fires N handlers.
- Correction from initial report: `notifyListeners()` after dispose does **not** throw — Stacked's `BaseViewModel` guards it (`if (!disposed)`) and silently no-ops. The leak, duplicate dialogs, and post-dispose work are the real harms.
- **Fix:** Store the `StreamSubscription`, cancel in `dispose()`; guard continuations after awaits with a disposed check.

### H-16. Web release channel likely broken: no cross-origin isolation on GitHub Pages *(new — verification sweep)*
- **Files:** `.github/workflows/release.yaml:308-348` (deploys web to GitHub Pages); `web/index.html:43-47` (loads `@mediapipe/tasks-genai` for `LlmInference`)
- GitHub Pages cannot set `COOP`/`COEP` response headers and `index.html` ships no `coi-serviceworker` shim, so `SharedArrayBuffer`/cross-origin isolation is unavailable. MediaPipe GenAI's threaded/SIMD WASM inference generally requires SAB. If so, the production web build loads but fails at first inference — same class of failure as C-1 (core function broken only in the release channel).
- **Fix:** Verify the SAB requirement for the pinned MediaPipe version; if required, self-host with COOP/COEP headers or add a `coi-serviceworker` shim.

### H-17. iOS release artifact is unsigned and hand-zipped — not distributable *(new — verification sweep)*
- **File:** `.github/workflows/release.yaml:112-123`
- Builds with `--no-codesign` then manually zips `Payload/` into an `.ipa`. Cannot be installed on devices or submitted to App Store/TestFlight. (C-2 covers Android only; this is the analogous iOS gap.)
- **Fix:** Sign with a distribution certificate/provisioning profile in CI, or explicitly document that this workflow produces inspection-only artifacts.

---

## MEDIUM

### M-1. Model downloads have no integrity verification
- **Files:** `lib/services/model_config.dart:183` (`sha256` field defined, never populated — verified all 8 models: 4 inference `:20-80`, 4 embedding `:86-154`); `model_management_service.dart:214-320`
- 110 MB–6.5 GB model binaries are downloaded and executed with zero hash verification. Corrupted CDN response or tampered file loads undetected. Infra already exists — `crypto` is a dependency and documents are hashed (`document_management_service.dart:143`).
- **Fix:** Populate `ModelDefinition.sha256` per model; verify digest before activation; fail closed on mismatch.

### M-2. `flutter_secure_storage` used without platform hardening options
- **File:** `lib/services/auth_token_service.dart:12`
- `const FlutterSecureStorage()` with no options, though the project's own `docs/implementation_plan_v3.md:1218-1219` specifies `AndroidOptions(encryptedSharedPreferences: true)` and `IOSOptions(accessibility: KeychainAccessibility.first_unlock)`. Default iOS keychain accessibility can allow the HF token into device backups.
- **Fix:** Construct with the documented `aOptions`/`iOptions`.

### M-3. Streaming path hardcodes context size 3, ignores `searchTopK`
- **File:** `lib/services/rag_service.dart:235,242,260` (vs `:141,150,168` using `settings.searchTopK`)
- Streamed answers silently use a different, non-configurable chunk count than non-streamed answers.
- **Fix:** Use `settings.searchTopK` in the streaming path.

### M-5. Reranking score parsing corrupts multi-number outputs
- **File:** `lib/services/reranking_service.dart:95` (clamp at `:98`)
- `replaceAll(RegExp('[^0-9.]'), '')` turns `"8/10"` into `"810"` → `double.tryParse` = 810.0 → clamps to 10.0. Rerank ordering silently wrong. (Reproduced during verification.)
- **Fix:** Extract first numeric token with `RegExp(r'\d+(\.\d+)?')`.

### M-6. Token budget computed against the wrong model
- **Files:** `lib/services/rag_service.dart:332-338,399-405` (vs `inference_model_provider.dart:29-38`)
- Budget math uses `ModelConfig.allModels.firstWhere(type == inference, orElse: …)` → always the first entry, `gemma3_270M` (maxTokens 1024), regardless of the user-active model (e.g. `gemma3_1B`, 2048). Also ignores `settings.maxTokens`, which the model provider *does* honor → prompt overflow or under-utilization.
- **Fix:** Source `maxTokens` from the same settings/provider used to load the model.

### M-7. `getModel` init race; `clearCache` leaks native model
- **File:** `lib/services/inference_model_provider.dart:21-42,67-69`
- Concurrent callers (RagService + QueryExpansion + Reranking within one query) can double-initialize; `clearCache` drops the old handle without dispose → leaked native sessions on model switch.
- **Fix:** Memoize the in-flight `Future<InferenceModel>`; dispose the old model before clearing.

### M-8. Prepared statements leak on execute error
- **File:** `lib/services/vector_store.dart:353-366,375-397,403-424`
- `..execute(...)..close()` cascades skip `close()` on throw (`insertEmbedding`, `insertDocument`); `insertEmbeddingsBatch` rollback path (`:394-397`) never closes its statement.
- **Fix:** `try { ... } finally { stmt.close(); }`.

### M-9. Similarity loop assumes uniform embedding dimensionality
- **File:** `lib/services/vector_store.dart:568-571`
- Iterates `i < queryEmbedding.length` indexing `storedEmbedding[i]` with no length check. Rows embedded by a different model (different dim) throw `RangeError` and break all search after a model switch.
- **Fix:** Skip/validate rows whose embedding length ≠ query length; long-term, tag rows with embedder id.

### M-10. `VectorStore.initialize()` has no error handling around DB open
- **File:** `lib/services/vector_store.dart:73-88`
- IO/permission failure on `sqlite3.open` crashes init opaquely.
- **Fix:** Wrap and surface a typed initialization error so the app can degrade gracefully.

### M-11. Contextualization failures swallowed silently
- **File:** `lib/services/contextual_retrieval_service.dart:103-106`
- `on Exception catch (_) { return ''; }` — chunks silently lose context enrichment with no log.
- **Fix:** Log (as reranking/expansion do) and/or propagate a failure indicator.

### M-12. Performance metrics misattributed
- **File:** `lib/services/rag_service.dart:130,177`
- `embeddingTime` includes query-expansion time; `generationTime` folds in reranking. Latency telemetry blames the wrong stage.
- **Fix:** Explicit per-stage start/stop deltas.

### M-13. Redundant query embedding on expansion path
- **File:** `lib/services/rag_service.dart:129,225` (vs `query_expansion_service.dart:77`)
- Query always embedded up-front, then discarded when expansion re-embeds every variant.
- **Fix:** Embed only on the non-expansion branch.

### M-14. Ingestion holds entire document + all embeddings in memory
- **Files:** `lib/services/document_parser_service.dart:59,119,141-154,160-189`; `document_management_service.dart:242-291`
- Peak memory ≈ file bytes + full extracted text + all chunk strings + all embedding vectors simultaneously; embedding accumulation runs on the main isolate. Low-end devices (the app's stated target) can OOM near the 50 MB limit.
- **Fix:** Insert embeddings incrementally per batch; consider paged extraction.

### M-15. Parser enforces no size limit itself (defense-in-depth gap)
- **File:** `lib/services/document_parser_service.dart:54-62`
- Size checks live only in the caller (`document_management_service.dart:95,136`); the parser (also constructed fresh inside the isolate at `:425`) will `readAsBytes` anything.
- **Fix:** Max-bytes guard inside the parser.

### M-16. SHA-256 of byte uploads runs on the main isolate
- **File:** `lib/services/document_management_service.dart:143`
- Multi-MB web/byte ingestion hashes synchronously on the UI thread (the file-path route streams correctly at `:397`).
- **Fix:** Hash inside the `compute()` isolate or in chunks.

### M-17. Settings sliders persist + notify on every drag tick
- **Files:** `lib/ui/views/settings/settings_view.dart:300-384`; `settings_viewmodel.dart:127-158`
- Verified: sliders supply only `onChanged` (no `onChangeEnd` anywhere); each setter awaits a `SharedPreferences` write + `notifyListeners()` per tick. Storage churn and jank.
- **Fix:** Update transient value on `onChanged`, persist on `onChangeEnd`.

### M-19. Deprecated `PlatformFile.bytes` (analyzer)
- **File:** `lib/services/document_management_service.dart:126,134`
- Flagged deprecated for OOM risk with large files; ties into M-14.
- **Fix:** Migrate to `readAsBytes()`/stream API per file_picker guidance (see also M-27 — the package itself is a beta).

### M-20. 401 detection via substring match
- **File:** `lib/ui/views/startup/startup_viewmodel.dart:64,83,175`
- Auth-required flow inferred from `errorMessage?.contains('401')`. Fragile; a typed `AuthenticationRequiredException` already exists (used in `chat_viewmodel.dart:204`).
- **Fix:** Propagate the typed exception instead of string matching.

### M-21. `firstWhere` without `orElse` on model recommendation
- **File:** `lib/ui/views/startup/startup_viewmodel.dart:139-142,194-198`
- Catalog/recommendation drift throws `StateError` → opaque startup failure.
- **Fix:** `orElse` fallback + explicit user-facing message.

### M-22. Duplicate-document TOCTOU race
- **File:** `lib/services/document_management_service.dart:106-111,145-148`
- `findByHash` → insert is not atomic; two simultaneous adds of the same file both insert. Verified: `content_hash` has only a non-UNIQUE index (`vector_store.dart:143-145`), no UNIQUE constraint.
- **Fix:** In-flight hash set, or a DB UNIQUE constraint on `content_hash`.

### M-23. CI Flutter version drift
- **Files:** `.github/workflows/main.yaml:22` (3.35.x) vs `release.yaml:46` (3.38.x) vs `pubspec.yaml:8` (^3.35.0)
- Releases build on a toolchain PR CI never tested.
- **Fix:** Align pins.

### M-24. macOS release step searches wrong flutter_gemma source; web pins mismatched JS runtime on CDN
- **Files:** `.github/workflows/release.yaml:252-262` — LiteRT-LM JAR step searches `.pub-cache/git` but `pubspec.lock:297-304` resolves flutter_gemma as *hosted* 1.2.1; the `find` returns nothing and the step only warns (`:260-261`), silently skipping — the `.dmg` may ship without the LiteRT-LM backend.
- `web/index.html:37-41` — loads `flutter_gemma@0.12.0` JS assets from jsDelivr while the Dart package is 1.2.1; `web/index.html:43-47` additionally loads `@mediapipe/tasks-genai@0.10.25` from jsDelivr. Version skew + two hard CDN runtime dependencies (blocked CDN = broken web app) + supply-chain surface.
- **Fix:** Point the CI step at `hosted/pub.dev/flutter_gemma-*` and fail loudly if absent; pin web JS to the matching version and self-host (see also H-16).

### M-25. Chunk-overlap setting is a no-op: active chunker ignores it; the settings-driven chunking path is dead code *(recharacterized after verification)*
- **Files:** `lib/services/smart_chunker.dart:16`; `document_management_service.dart:438`; `lib/services/rag_service.dart:292-303,466-547`
- The active ingestion path is `SmartChunker.chunk()` (called from the parse isolate at `document_management_service.dart:438`), which hardcodes `overlapChars = 50` and never reads `chunkOverlapPercent`. The only consumer of the setting is `RagService.splitIntoChunks` via `RagService.ingestDocument` — which is **never invoked anywhere in lib/ or test/** (dead code; its `targetWords` parameter is also dead within the function).
- **Production impact:** The chunk-overlap slider in Settings does nothing; maintainers reading `RagService.ingestDocument` are reading a fiction.
- **Fix:** Wire `SmartChunker` to `RagSettingsService`; delete the dead `RagService` ingestion/chunking path.

### M-26. Syncfusion commercial license never registered *(new — verification sweep)*
- **Files:** `pubspec.yaml:37` (`syncfusion_flutter_pdf`); no `registerLicense` anywhere in repo (grep: 0 hits)
- Syncfusion is not free for general commercial distribution; the non-UI PDF package runs without a key, so nothing fails at runtime — the exposure is legal, not technical.
- **Fix:** Confirm eligibility for Syncfusion's Community License (revenue/headcount limits) or acquire and register a commercial license; document the decision.

### M-27. `file_picker` pinned to a beta in production *(new — verification sweep)*
- **Files:** `pubspec.yaml:17`, `pubspec.lock:267` → `12.0.0-beta.7`
- Pre-release dependency on the primary document-ingestion entry point; no stability guarantees.
- **Fix:** Move to a stable `file_picker` release; reconcile with the M-19 deprecated-`bytes` migration.

### M-28. `ModelManagementService.initialize()` has no idempotency/concurrency guard *(new — verification sweep)*
- **Files:** `lib/services/model_management_service.dart:75-143`; callers `startup_viewmodel.dart:129` (awaited) and `settings_viewmodel.dart:74` (unawaited, on every Settings navigation)
- Re-runs `_activateInferenceModel`/`_activateEmbeddingModel`, mutating shared `_models` and re-invoking native `FlutterGemma.install*` concurrently with startup → wasted native reloads and possible plugin-state races.
- **Fix:** Guard with a memoized in-flight future / initialized flag; don't re-run full init from Settings.

### M-29. iOS file sharing exposes the entire document/chat database *(new — verification sweep)*
- **Files:** `ios/Runner/Info.plist:55-56` (`UIFileSharingEnabled=true`); `lib/services/vector_store_path_native.dart:7` (DB under `getApplicationDocumentsDirectory()`)
- All ingested document text, chunks, and chat history are user-extractable via Finder/iTunes file sharing. May be intentional; if not, it's a privacy leak.
- **Fix:** Store the DB (and models) under Application Support, or disable file sharing.

---

## LOW

| # | File:Line | Issue | Fix |
|---|---|---|---|
| L-1 | `lib/services/auth_token_service.dart:38-44` | `--dart-define` HF token would be baked into the shipped binary and auto-persisted (latent — verified no workflow passes `--dart-define`) | Gate behind `kDebugMode` or drop env fallback |
| L-2 | `lib/services/logging_service.dart:5-33`, `model_management_service.dart` (21 `DEBUG:` log sites), `startup_viewmodel.dart:41,127,130,186` | No environment-based log level; verbose DEBUG + device metadata logged in production (`adb logcat` readable). `app.logger.dart:174` gates correctly; `LoggingService` and raw `dart:developer` calls do not | Route all logging through a level-aware service reading `EnvironmentService`; min level `warning` in prod |
| L-3 | `lib/bootstrap.dart:48-50` | `FlutterError.onError` only logs; no `runZonedGuarded`, no crash reporting — production crashes invisible | Add `runZonedGuarded` + a crash reporter (or at minimum persisted error log) |
| L-4 | `lib/bootstrap.dart` (absent) | No lifecycle observer; `VectorStore.close()` has zero callers in app code — in-flight batch writes can be lost on process kill | Close DB on `AppLifecycleState.detached` |
| L-5 | `macos/Runner/Release.entitlements:7-8` | `disable-library-validation=true` in Release (likely required by flutter_gemma dylibs; sandbox still on) | Confirm necessity; document justification |
| L-6 | `pubspec.yaml:28,36,47` | `logger: any`, `stacked_shared: any`, `path_provider_platform_interface: any` — non-reproducible resolves | Pin caret ranges |
| L-7 | `lib/services/document_management_service.dart:178,297,319,340-342` | Byte-ingested docs store filename as `filePath`; `refreshDocument` then throws `FileSystemException('Original file not found')` | Track `hasSourceFile`; skip file-based refresh for byte docs |
| L-8 | `lib/services/reranking_service.dart:75` | Hardcodes `500`; `rag_constants.dart:29` defines `maxCharsForReranking = 500` for exactly this | Use the constant |
| L-9 | `lib/services/vector_store.dart:187,190`, `rag_token_manager.dart:38`, `contextual_retrieval_service.dart:49,59-63` | Hardcoded pool sizes / token limits / magic ratios that belong in `RagConstants`/settings | Centralize |
| L-10 | `lib/services/rag_settings_service.dart:47` → `vector_store.dart:524` | `semanticWeight` setter clamps [0,1] on write, but `initialize()` reads persisted value unclamped (see L-24); out-of-range escape would invert ranking | Clamp on read |
| L-11 | `lib/services/rag_service.dart:341` | Token budget can go negative on very long queries; silent "No relevant context found." | Clamp to 0 + log |
| L-14 | `lib/ui/views/chat/chat_viewmodel.dart:166` | Hardcoded `.take(10)` on history — *corrected:* the `maxHistoryMessages` setting IS applied downstream (`rag_service.dart:352,419`, clamped 0–5), so the 10 is a redundant upper bound, not an ignored setting. Code-clarity issue only | Use the setting value at the single source |
| L-15 | `lib/ui/views/startup/startup_viewmodel.dart:241-248` | `retry()` directly mutates service-owned model objects | Add `resetErroredModels()` on the service |
| L-16 | `lib/ui/views/chat/chat_view.dart:121-124` | State mutation (`onScrolled`) inside `builder()` | Post-frame callback |
| L-17 | `lib/ui/views/document_library/document_library_view.dart:143-146` | `confirmDismiss` always returns false → double-confirm semantics, janky animation | Return actual confirmation result |
| L-18 | `lib/services/document_parser_service.dart:168-173` | HTML strip leaves entities and `<script>/<style>` bodies in EPUB text → pollutes embeddings | Unescape entities; strip script/style |
| L-19 | `lib/ui/views/chat/widgets/chat_input.dart:28,121` | Whitespace-only send passes (no trim); Enter submits while processing (dropped downstream) | Trim-check; gate on `isProcessing` |
| L-20 | `lib/ui/views/chat/chat_viewmodel.dart:223-238` | Source chip with null `documentId` looks tappable, does nothing | Disable visually or show metadata dialog |
| L-21 | `android/app/build.gradle.kts:31` | Stale template TODO comment (`applicationId` is actually set correctly at `:32`) | Remove comment |
| L-22 | `lib/services/smart_chunker.dart:195`, `rag_service.dart:524` | Chunk step `i += maxChars - overlapChars` lacks a `step >= 1` guard — *downgraded from Medium:* unreachable via UI (setter clamps overlap 0–0.3 at `rag_settings_service.dart:74`; active chunker hardcodes overlap 50). Defense-in-depth only; the unclamped read path (L-24) is the only theoretical route | Guard `step >= 1` |
| L-23 | `lib/models/document.dart:30-32` | Hard casts (`as int`, `as String`) throw on null — *downgraded from Medium:* current DDL declares these columns `NOT NULL` (`vector_store.dart:131-133`), so only legacy/schema-drift rows trigger it. Becomes real the moment H-13's missing migration path bites | Null-safe casts with defaults |
| L-24 | `lib/services/rag_settings_service.dart:44-58` | `initialize()` reads all persisted settings (`getDouble`/`getInt`) with **no clamping** — setters clamp on write, but prefs written by an older/tampered build load raw, bypassing every clamp (undercuts L-10, L-22 mitigations) | Clamp on read in `initialize()` |
| L-25 | `ios/Runner/Info.plist` (key absent) | No `ITSAppUsesNonExemptEncryption` — every TestFlight/App Store upload prompts for export compliance, blocking automated submission | Add key (almost certainly `false`) |
| L-26 | `lib/app/main_app.dart:13,16-17`; `document_library_viewmodel.dart:43-45,72-74,86-89` | l10n fully wired (`en`+`es`, `generate: true`) but user-facing strings hardcoded in English throughout — Spanish locale non-functional despite setup | Route strings through `AppLocalizations` |
| L-27 | `android/app/src/main/AndroidManifest.xml` | No `POST_NOTIFICATIONS` permission; on Android 13+ download progress/FGS notifications (if the downloader posts them — unverified) are silently suppressed | Declare + runtime-request if download notifications are used |
| L-28 | `web/index.html:22` | Ships Very Good CLI template meta description ("A Very Good Project created by Very Good CLI.") | Set real description |
| L-29 | `pubspec.lock:884` | `sqlite3_flutter_libs` resolves to `0.6.0+eol` — the `+eol` build tag suggests an end-of-life release line (unconfirmed) | Verify maintenance status on pub.dev; move to maintained release if EOL confirmed |

*Removed after verification:* the initially-reported `chat_repository.dart:94` "`as double` throws on int-serialized scores" finding was **wrong** — `SearchResult.score` is a typed `double` and Dart's JSON round-trip preserves it (`8.0` encodes with the decimal point); no code path writes an int score.

---

## Test Coverage

124 tests, all passing. Coverage by module:

| Covered (substantive) | Zero coverage |
|---|---|
| auth_token_service, chat_repository, contextual_retrieval, device_capability, document_management, document_parser, environment, model_management, query_expansion, rag_token_manager, reranking, smart_chunker, vector_store, startup_viewmodel, startup_view (widget) | **chat_viewmodel** (primary user flow: send/stream/persist/dispose), **embedding_service**, **inference_model_provider**, **rag_settings_service** (only ever mocked), **model_recommendation_service**, settings/document_library/document_detail viewmodels, all views except startup |

Specific gaps on critical paths:
1. **`chat_viewmodel`** — largest untested behavioral surface; also where H-6/H-7 live.
2. **`rag_service`** — `test/services/rag_service_test.dart:74-122` covers one happy path only. Untested: expansion path, reranking path, contextual retrieval, `documentIds` filter, empty-results path, generation errors.
3. **`vector_store_test.dart:102-105`** — "combines scores correctly" is an empty placeholder with no assertions; hybrid merge weighting effectively unverified.
4. **`embedding_service`** — the "no active embedder" failure mode real users hit is untested.

---

## Positive Findings (verified, no action)

- **SQL injection: clean.** All dynamic SQL uses `?` placeholders, including `IN (...)` built via `List.filled(n, '?')`; FTS input sanitized (`vector_store.dart:496-505`, re-verified: strips operators/quotes before `MATCH ?`).
- **No hardcoded secrets** anywhere in `lib/`, platform dirs, or CI. `key.properties`/`*.jks` gitignored and absent. Token value never logged.
- **HTTPS-only** model downloads (re-verified all 8 model+tokenizer URLs); no `usesCleartextTraffic`, no ATS exceptions.
- Token migration SharedPreferences → secure storage deletes the insecure copy (`auth_token_service.dart:29-34`).
- Document dedup by SHA-256 + size limits on both ingestion paths. Settings setters clamp inputs **on write** (read path is not clamped — see L-24).
- Transactions in batch insert/delete correctly `ROLLBACK`/`rethrow` (re-verified; M-8's statement-close leak is a separate point); cosine division-by-zero handled.
- `VectorStore.mergeResults` RRF is implemented correctly with per-list ranks — the RRF bug (H-4) exists only in `query_expansion_service`.
- Parsing runs in a `compute()` isolate; token dialog uses `obscureText`.
- Dependabot enabled; R8/ProGuard rules correct for flutter_gemma (no sqlite keep rule needed — native `.so` via JNI).
- No Dockerfile needed — client-only app; no server component.

---

## Verification

Every finding was adversarially re-verified same-day by independent review against source (including an exhaustive pub-cache manifest-merger check for C-1 and framework-behavior checks against the Stacked package for the dispose-related claims). Outcome:

- **57 of 59 original findings confirmed** (all line references accurate).
- **1 removed** as false (chat_repository score cast — see LOW footnote).
- **1 downgraded Critical→High** (H-15, ex-C-5: no crash occurs; leak and duplicate-dialog harm remain).
- **2 downgraded Medium→Low** (L-22 ex-M-4: trigger unreachable via UI; L-23 ex-M-18: columns are `NOT NULL` in current schema).
- **1 recharacterized** (M-25: the dead-code direction was inverted in the original — `SmartChunker` is the active path, `RagService.splitIntoChunks` is dead; net user impact is larger than originally stated: the overlap setting is a no-op).
- **2 wording corrections** (H-7: post-dispose notify is harmless, other harms stand; H-8: Dart memory, not native handle).
- **11 new findings added** by a dedicated completeness sweep (H-16, H-17, M-26–M-29, L-24–L-29 minus recharacterizations).

---

## Suggested Remediation Order

1. **Release blockers (hours):** C-1 (INTERNET permission), C-2 (Android signing), H-17 (iOS signing — or document as non-distributable), H-12 (versionCode), H-14 (CI test gate), M-23 (toolchain pin), H-16 (verify web SAB requirement before shipping web).
2. **Data-integrity before first ship (day):** H-13 (stamp `PRAGMA user_version` now — retrofitting after release is much harder), C-4 (DOCX encoding), M-9 (embedding dim guard), L-23 (null-safe Document.fromJson), M-26 (Syncfusion license decision — legal, not code).
3. **Stability (days):** H-15/H-5/H-6/H-7 (listener leaks + races), H-1 (timeouts), H-8/H-9/H-10/H-11 (error handling), M-7/M-8 (resource leaks), M-28 (init guard).
4. **Scale & quality (next iteration):** C-3 (vector scan), H-2/H-3 (serial LLM calls), H-4/M-5 (ranking bugs), M-1 (model checksums), M-14 (ingestion memory), M-25 (wire chunk settings, delete dead path), test coverage on chat_viewmodel + rag_service branches.

*Generated by production audit 2026-07-07; revised same day after adversarial verification. No code was modified.*
