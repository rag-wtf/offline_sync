# Production Readiness Audit — offline_sync (Round 3)

**Date:** 2026-09-04
**Branch:** `main` @ `27366e5` (clean working tree before and after the audit)
**Scope:** Full codebase — every non-generated file under `lib/`, every file under `test/`, Android/iOS/macOS/Linux/Windows/web platform config, CI/release workflows, `pubspec.yaml`/`pubspec.lock`, and the installed `flutter_gemma` 1.7.0 plugin sources where the app's behavior depends on them.
**Constraint honored:** Audit only. No application code, tests, or configuration were modified. Public API unchanged. (Two throwaway probe scripts were run from the scratchpad/`build/` directory and removed; see Appendix A.)
**Review pass (2026-09-04, same day):** every file:line reference, plugin fact and count below was re-checked against `main` @ `27366e5`; the analyzer, the full test suite and the probes were re-run (Appendix A). Corrections are folded in. The review added one Critical (C-2, web checksum path) and one Low (L-19), corrected the Round 2 tally (27 of 35 fixed, not 25 of 30), and fixed a dozen stale line references (notably `vector_store_test.dart`, which has 637 lines, not 1,300+).
**Prior audits:** 2026-07-07 (Round 1) and 2026-08-28 (Round 2, `e83b7e3`). Section "Status of the Round 2 audit" records what was verified fixed and what is carried forward.

---

## Stack

| Layer | What is used |
|---|---|
| Framework | Flutter 3.47.2 / Dart 3.13.2 locally; `pubspec.yaml` requires Flutter `>=3.44.0`, Dart `>=3.12.0`; CI pins `3.44.x` |
| Architecture | Stacked MVVM (`stacked` 3.5.0) + `get_it` locator via `stacked_generator` codegen; three flavors (`main_development|staging|production.dart`) |
| Storage | `sqlite3` 3.5.2 (FTS5 + base64 Float32 embeddings, `PRAGMA user_version = 3`) as vector store, document inventory and chat history; `shared_preferences` for settings and crash logs; `flutter_secure_storage` 11.0.0 for the Hugging Face token; sqlite3 WASM + IndexedDB VFS on web |
| AI | `flutter_gemma` 1.7.0 with `flutter_gemma_litertlm` 1.6.1 (`.litertlm` inference, `.tflite` embeddings) and `flutter_gemma_mediapipe` 1.0.5 (`.task` inference, Android/iOS/web only); models downloaded from Hugging Face via `background_downloader` 9.5.9 |
| Parsing | `syncfusion_flutter_pdf` 33.2.13, `archive` 4.2.0 + `xml` 6.6.1 (DOCX), `epub_plus` 5.1.0 |
| Domain | Fully offline on-device RAG: ingest → chunk → embed → hybrid (FTS5 + cosine, RRF) search → optional expansion / rerank / contextual retrieval → streamed generation |
| Targets built by `release.yaml` | Android (signed APK/AAB), iOS (unsigned, inspection only), Linux (AppImage + tarball), macOS (DMG), Windows (zip), Web (GitHub Pages) |

## Verification status (run 2026-09-04 on this machine)

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 0 infos |
| `flutter test --coverage` (full suite) | **368 passed, 0 failed** (39 s; review re-run 32 s, same result) |
| Line coverage (`coverage/lcov.info`) | 3,467 / 3,562 = **97.33%** (identical on re-run; CI gate is 95%; see the coverage note under Test coverage) |
| `flutter pub get` security advisories | None reported by pub |
| Outdated dependencies (`flutter pub outdated`) | 10 packages have newer major versions blocked by constraints (`get_it` 9, `xml` 7, `syncfusion_*` 34, `flex_seed_scheme` 5, …); none is a known vulnerability |
| FTS5 query probe (Appendix A.1) | Every natural-language question containing `?` `'` `,` `!` `.` `+` `@` is rejected by FTS5 with `fts5: syntax error`; only bare words match; the operator regex also deletes the English words "and/or/not/near" → confirms H-1 |
| SHA-256 throughput probe (Appendix A.2) | package:crypto sustains 146–148 MB/s on this desktop (x64 JIT, two runs); mobile AOT is typically 2–4× slower → quantifies H-2 |
| Web checksum path (Appendix A.4) | The app keeps only a `getModelFilePaths` entry whose basename equals the model file name; the plugin's web manager returns `blob:` URLs, so no entry ever matches → C-2. Traced through installed plugin sources; **not executed in a browser** |
| GitHub Actions `main` @ `27366e5` | **Red.** Run 33813259973 (2026-09-03) fails in the `spell-check` job on `docs/superpowers/plans/2026-09-03-model-download-fixes.md` (five unknown words: three UK spellings of "license", one Android package prefix, one git term); the `build` job (format/analyze/test/95% gate) passed. This report itself uses six technical tokens the dictionary lacks (`opfs`, `xcconfig`, `xcodeproj`, `pbxproj`, `linuxdeploy`, `Metaspace`) — add them to `.github/cspell.json` when committing it, or the same job fails again |
| Working tree | Clean. One empty (0-byte) untracked file with a code-fragment name appeared in the repo root during the run; it could not be reproduced by re-running the suspected shell loop or the two tests that reference that symbol, and was removed. It is not part of the codebase. |

## Status of the Round 2 audit (2026-08-28)

Verified fixed against current source (each checked in code, not taken from commit messages):

- **H-1** `InferenceModelProvider.clearCache()` is now called on model switch and on `setMaxTokens` (`model_management_service.dart:570-573`, `rag_settings_service.dart:128-130,137-139`).
- **H-2** Generation streams have a 30 s inactivity timeout (`rag_service.dart:391-393,465-467`).
- **H-3** Prompt budget uses `settings.maxTokens ?? modelConfig.maxTokens` (`rag_service.dart:344,414`).
- **H-4** Vectors carry `embedding_model_id` (schema v3) and search filters on it (`vector_store.dart:79,125,286-294`) — but see M-4 for the missing user-facing half.
- **H-5** macOS entitlements now include `network.client` and `files.user-selected.read-only` (both entitlement files).
- **M-1** Reranking scores sequentially (`reranking_service.dart:25-36`). **M-3** chunk overlap threaded through the isolate params (`document_management_service.dart:123-133,480`). **M-4** SHA-256 digests populated for all 8 models. **M-5** upsert is `ON CONFLICT(id) DO UPDATE` (`vector_store.dart:513-524`). **M-6** `initialize()` memoized (`model_management_service.dart:164-173`). **M-7** settings default keyed to the active model. **M-8** chunks ordered by `metadata.seq`. **M-9** hand-rolled turn markers removed. **M-10** embeddings inserted per 10-chunk batch. **M-11** Syncfusion Community License eligibility recorded in `docs/licensing.md`.
- **Lows:** clamp-on-read (L-1), typed auth failure kinds (L-2), statement `try/finally` (L-3), history `skip(2)` (L-5), `PlatformDispatcher.onError` instead of a zone (L-6), `ORDER BY timestamp, id` (L-8), `recursive_triggers` (L-9), delete `try/finally` (L-10), MediaPipe bundle self-hosted (L-13), Float32 storage (L-14), negative budget clamp (L-15), analyzer infos (L-16), `embedding_codec.dart` and `RagService.ingestDocument` deleted (part of L-12).

**Not fixed / only partially fixed (carried into this report):**

- Round 2 **M-13** (LLM sessions never closed) — no `close()` call on any chat or session exists in `lib/` → **M-1**.
- Round 2 **M-14** (corpus in backed-up storage) — the DB moved from `Documents` to `Application Support`, which stops Files-app visibility but does not remove it from iCloud/iTunes backup, and Android's backup posture was never set → **H-3**.
- Round 2 **L-4** (startup hashing) — the verification cache is a static in-memory `Set`, so every cold start re-hashes → **H-2**.
- Round 2 **M-2** (recall bounded by keyword candidates) → **M-6**. **L-7** (crash logs never surfaced) → **M-5**. **L-11** (partial l10n) → **L-2**. Remaining dead paths from **L-12** → **L-1**.
- Round 2 **M-12** (coverage counts instrumented lines only) — 125 `coverage:ignore` markers remain (57 start/end regions + 8 single lines + 3 whole files, down from 139 markers / 76 regions), and the gate was lowered from 100% to 95% (`.github/workflows/main.yaml:24`, commit `aa73cbd`, 2026-09-01) → Test coverage section.

Tally: Round 2 listed 35 items (5 High, 14 Medium, 16 Low). 27 are verified fixed, L-12 partially, and the 7 above are carried.

## Summary

| Severity | Count | Theme |
|---|---|---|
| Critical | 2 | Desktop builds ship models the desktop engine cannot run; the web build can never pass checksum verification, so no web user leaves the startup screen |
| High | 5 | Retrieval silently degraded by punctuation; multi-GB re-hash on every launch; corpus in OS backups despite the privacy promise; macOS ships template identity; multi-GB downloads without consent and with a hard-coded GPU assumption |
| Medium | 11 | Session lifecycle, Settings error handling, init error boundary, embedder switch UX, storage/data controls, recall bound, context-size mismatch, `Error` vs `Exception` gaps (incl. a poisoned `initialize()` future), brittle checksum pins, CI build gap, fallback-id bug |
| Low | 19 | Dead code, l10n drift, decode heuristic, DI inconsistency, web flush, pipeline pinning, identity consistency, legacy-row embedder filter, hygiene |

**Overall verdict:** Android is close to a controlled/beta release once H-1, H-2 and H-5 are addressed (H-3 is a policy decision that should be made before the first public build). **Windows, Linux, macOS and web are not shippable today**: C-1 means most desktop machines download a model that cannot run, macOS additionally ships the Flutter template bundle identifier (H-4), and C-2 stops every web launch at checksum verification (with H-1 waiting behind it). iOS remains intentionally unsigned. The five Highs are all reachable from a normal first launch, not from unusual settings.

---

## CRITICAL

### C-1. Desktop builds recommend and download MediaPipe `.task` models that no desktop engine can run — Windows/Linux/macOS are unusable on most hardware

- **Files:** `lib/services/model_recommendation_service.dart:137-158` (`_determineDeviceTier` uses only RAM, `hasGpu`, storage; `DeviceCapabilities.platform` is never consulted), `:62-94` (tier → model); `lib/services/model_config.dart:36-93` (catalog: low = `gemma3-270m-it-q8.task`, mid = `Gemma3-1B-IT_…_ekv4096.litertlm`, high = `gemma-3n-E2B-it-int4.task`, premium = `gemma-3n-E4B-it-int4.task`); `lib/services/device_capability_service.dart:172,189,206` (`hasGpu: true` hard-coded for Linux/macOS/Windows); `lib/ui/views/startup/startup_viewmodel.dart:139-190` (auto-download of the recommended pair); `lib/bootstrap.dart:88-97` (registers `LiteRtLmEngine` + `MediaPipeEngine`).
- **Plugin facts (verified in installed sources):** `flutter_gemma_mediapipe` declares only `android` and `ios` plugin platforms (`flutter_gemma_mediapipe-1.0.5/pubspec.yaml`); its web support is a pure-Dart conditional export (`lib/flutter_gemma_mediapipe.dart` → `src/mediapipe_engine_web.dart`) and there is no desktop implementation at all. `LiteRtLmEngine.canHandle` accepts only `ModelFileType.litertlm` (`flutter_gemma_litertlm-1.6.1/lib/src/litert_lm_engine.dart:89-90`). The desktop host resolves the engine through the registry (`flutter_gemma-1.7.0/lib/desktop/flutter_gemma_desktop.dart:340-373`): with no matching engine it throws `StateError('No inference engine can handle this model …')` — the case its comment describes ("Desktop is litertlm-only; a `.task` request would simply find no matching engine", `:341-345`). Because `bootstrap.dart:88-97` registers `MediaPipeEngine()` on every platform, the `.task` spec is in practice matched to `MediaPipeEngine` (`mediapipe_engine.dart:28-30`), whose `createModel` drives a pigeon channel with no macOS/Windows/Linux host, so the call fails with `MissingPluginException` instead. Either way no `.task` model can be created on desktop. The project's own `docs/platform-setup-review.md:120` states the same.
- **What happens in production:** A Windows/Linux/macOS machine with >8 GB RAM (i.e. nearly every current desktop) is classified `high` or `premium`, downloads 3.1–6.5 GB, then every chat message fails when the model is created. The user sees `InferenceModelProvider`'s wrapped message "Failed to get active inference model: … The model may still be downloading. Please wait and try again." (`inference_model_provider.dart:50-53`) — misleading, and there is no recovery path except manually switching to the mid tier in Settings (which only appears once two inference models are downloaded, `settings_view.dart:47`). Machines with <4 GB RAM get the 270M `.task` model and fail the same way. Only the mid tier works on desktop. The manual verification plan's desktop item is unchecked (`docs/manual_verification_plan.md:638-640`), so this was never exercised.
- **Why Critical:** the release workflow publishes desktop artifacts, and the first-run flow produces a non-functional app on the majority of desktop hardware after a multi-gigabyte download.
- **Fix:** Make model compatibility platform-aware: add a `supportedPlatforms`/`fileType` gate to `ModelDefinition`, filter `InferenceModels.all` by platform in `ModelRecommendationService` (desktop → `.litertlm` only; today that leaves a single option, so add `.litertlm` variants for the other tiers or pin desktop to the 1B model), and refuse to download/activate an incompatible model with a clear message. Add a unit test per platform × tier asserting the recommended model's file type is runnable there. Until then, remove Windows/Linux/macOS from the release matrix or document them as unsupported.

### C-2. On web, post-download checksum verification can never succeed — the low-tier models are marked errored on every launch and the app never leaves the startup screen *(added by the review pass)*

- **Files:** `lib/services/model_management_service.dart:3` (`import 'dart:io'`; the service has no `kIsWeb` branch), `:450-456` (`_verifyDeclaredChecksum` runs after every download on every platform; `:215-219` runs it again on each launch for anything the plugin reports installed), `:647-659` (unresolvable path → status `error`, "Checksum verification unavailable: installed file path not exposed", fail closed), `:661-663` (`File(installedModelPath)` / `statSync()`), `:709-719` (`getModelFilePaths` → keep the entry whose basename equals `definition.fileName`). Plugin (installed sources): `flutter_gemma-1.7.0/lib/core/model_management/managers/web_model_manager.dart:560-600` returns the URLs registered by the web download path — `blob:` URLs on the Cache API path the app enables via `cache_api.js` (`web_download_service.dart:145`, `web_cache_service.dart:474,480`) or `opfs://<filename>` markers (`web_download_service.dart:199,231`); `web_file_system_service.dart:160-170`.
- **What happens:** For a `blob:https://host/<uuid>` URL the basename is the UUID, so the match at `:716-717` fails, `_resolveInstalledModelPath` returns `null`, and the model is set to `error` with the "path not exposed" message; `_statusController.addError` fires, the startup subscription's `onError` displays it, and `runStartupLogic` ends in "Failed to download models. Please retry." (`startup_viewmodel.dart:205-218`). Retry re-runs the identical sequence (the plugin serves the cached blob), so the app is stuck on the startup screen indefinitely. If the plugin's OPFS path is active instead, the marker's basename does match and `File('opfs://…')` throws `UnsupportedError` (dart:io is stubbed on the web target) — an `Error` that escapes the `on Exception` handler at `:497` (M-8), leaves the model in `downloading`, and surfaces as `setError('Unsupported operation: …')` at `:222-225`. Both branches are terminal. Gecko-64 (the web tier's embedding model) has carried a digest since Round 1, so this has been true since checksum enforcement became fail-closed; Round 2's "Web: ready with caveats" and this report's original "Web works within the low tier" were both written without running the web build (`docs/manual_verification_plan.md:630-636` — every web item unchecked; `docs/web-deployment.md` covers deployment, not a run).
- **Verification:** traced statically through the app and the installed plugin sources; the app's basename matching was probed against the three URL shapes (Appendix A.4). **Not executed in a browser** — `flutter run -d chrome -t lib/main_production.dart` is the one-step confirmation.
- **Why Critical:** `release.yaml` publishes the web build to GitHub Pages, and no web user can get past the first screen.
- **Fix:** Guard the on-disk verification with `kIsWeb` and document that web integrity relies on HTTPS plus the plugin's Cache API (or, if a digest check is wanted on web, `fetch()` the blob URL and stream it through SHA-256 instead of `dart:io`). Treat "path not exposed" on web as "verified by the plugin", not as an error. Add a `ModelManagementService` test whose injected resolver returns a `blob:` URL and assert the model reaches `downloaded`. Until then, drop web from the release matrix.

---

## HIGH

### H-1. FTS5 query sanitizer lets ordinary punctuation through — full-text search fails on almost every real question and retrieval silently degrades to a recency-ordered `LIKE` scan

- **Files:** `lib/services/vector_store.dart:71-75` (`_specialCharsRegex` strips only `" * - ( ) ^ :`), `:631-637` (`_sanitizeFtsQuery`), `:338-384` (`_fts5Search`; any `SqliteException` → `_fallbackKeywordSearch`), `:386-439` (fallback: words >2 chars, `LOWER(content) LIKE`, flat `score: 0.5`, `ORDER BY created_at DESC LIMIT 100`), `:243-265` (`hybridSearch` uses the keyword result ids as the candidate set for semantic scoring).
- **Verified (Appendix A.1, sqlite 3.53.4, re-run during the review):** `What is the refund policy?` → `fts5: syntax error near "?"`; `What's the shipping time` → `near "'"`; `returns, refunds and shipping` → `near ","`; `How long does shipping take!` → `near "!"`; `C++ pointers` → `near "+"`; `a.b@c.com` → `near "."`; only `refund policy` matched. FTS5 bare words may contain only alphanumerics, `_` and non-ASCII characters; everything else must be quoted. A second defect in the same sanitizer: `_sqlOperatorsRegex` is case-insensitive and word-bounded, so it deletes the ordinary English words "and", "or", "not" and "near" (`This is not working` → `MATCH "This is working"`), inverting the meaning of negated questions. `SqliteException implements Exception` (`sqlite3-3.5.2/lib/src/exception.dart:9`), which is why the `on Exception` at `:377` swallows every one of these.
- **Production impact:** BM25 ranking is effectively never used for questions (most end in `?` or contain an apostrophe). The fallback returns the 100 most recently ingested chunks that contain any 3+ letter word from the question (including "what", "the"), with identical scores, and that recency-ordered set then gates semantic search. In a corpus larger than ~100 chunks, the chunk that actually answers the question is frequently not even scored. The silent `catch → fallback` means nothing is logged and no test noticed: the existing vector-store tests only use bare words (`vector_store_test.dart:156,184`), the "operator-only" test (`:195-196`) passes because the fallback returns nothing, and the fallback test (`:199-231`) reaches `_fallbackKeywordSearch` by dropping the FTS table rather than by sending a real question.
- **Fix:** Tokenize the query into `[\p{L}\p{N}_]+` tokens and quote each (`"refund" "policy"`), skip FTS when no token survives, and log at warning level when the fallback path is taken. Do not gate semantic search on fallback candidates (or rank fallback matches by number of matched terms rather than recency). Add tests with punctuation, apostrophes and an empty query asserting FTS is used (e.g. via a spy on the fallback).

### H-2. Every cold start re-hashes every installed model in pure Dart on the UI isolate — tens of seconds to minutes of "Initializing AI Models…" on each launch

- **Files:** `lib/services/model_management_service.dart:178-225` (`Future.wait` over all models; `_verifyDeclaredChecksum` for each installed one), `:624` (`static final Set<String> _verifiedChecksumCache` — process-lifetime only), `:662-676` (cache key check, then `verifyFileSha256`), `:753-765` (`sha256.bind(file.openRead())` on the calling isolate); `lib/ui/views/startup/startup_viewmodel.dart:153-156` (awaited during startup, status stuck on "Selecting optimal models…").
- **Verified (Appendix A.2):** package:crypto SHA-256 runs at ~148 MB/s on this x64 desktop under JIT. At that rate the mid tier (584 MB + 179 MB) costs ~5 s, high (3.1 GB + 179 MB) ~23 s, premium (6.5 GB + 183 MB) ~46 s — per launch, before the app is usable. Mobile AOT on ARM is typically 2–4× slower, and the hashing competes with the UI thread (chunks are processed on the main isolate between I/O events). Round 2's L-4 asked for a persisted cache; the implemented cache never survives a restart, so it only dedupes within one session.
- **Fix:** Persist the verification result (path, size, mtime, expected digest) in `SharedPreferences` and skip hashing when unchanged; hash inside `compute()` when it must run; verify immediately after download (already done) and treat the persisted record as authoritative on later launches. Consider verifying only the model that will be activated instead of all installed ones.

### H-3. The knowledge base, chat history and model files sit inside OS backup scope on iOS and Android — the "no data leaves your device" promise is not enforced

- **Files:** `lib/services/vector_store_path_native.dart:8-11` (`getApplicationSupportDirectory()` → `Library/Application Support`, which iOS backs up to iCloud/Finder by default; only `Caches` and `tmp` are excluded); `android/app/src/main/AndroidManifest.xml:14-17` (`<application>` declares neither `android:allowBackup` nor `dataExtractionRules`/`fullBackupContent` → Auto Backup defaults on); plugin storage: `flutter_gemma-1.7.0/lib/core/infrastructure/platform_file_system_service.dart:224-225` puts model files in `getApplicationDocumentsDirectory()` on Android/iOS, and neither the plugin's iOS code nor the app sets `NSURLIsExcludedFromBackupKey`; product claim `web/index.html:22`.
- **Production impact:** On iOS the full chunk text of every ingested document, the document inventory, the complete chat history (`vectors.db`) and multi-gigabyte model files are included in iCloud backups — leaving the device and consuming the user's iCloud quota (many users have the free 5 GB). On Android, the DB and models fall under Auto Backup; because the models push the app far past the 25 MB cloud quota, cloud backups will most likely fail entirely (also a support issue), while Android 12+ device-to-device transfers copy everything. Round 2's fix changed the directory but not the backup behavior.
- **Fix:** Decide and document the backup posture. Recommended: exclude `vectors.db` and the model directory from backup (`NSURLIsExcludedFromBackupKey` on iOS/macOS via a small platform channel or by storing them under a directory you mark excluded; `android:allowBackup="false"` or `dataExtractionRules` excluding `files/` and `app_flutter/` on Android). State the resulting behavior in the privacy copy.

### H-4. The macOS production build ships the Flutter template identity: bundle ID `com.example.myApp`, "Copyright © 2023 com.example"

- **Files:** `macos/Runner/Configs/AppInfo.xcconfig:8-14` (`PRODUCT_NAME = my_app`, `PRODUCT_BUNDLE_IDENTIFIER = com.example.myApp`, `PRODUCT_COPYRIGHT = Copyright © 2023 com.example…`); `macos/Runner.xcodeproj/project.pbxproj:598-637` (Debug/Release-production configurations use `AppInfo.xcconfig` as base and override only `PRODUCT_NAME`; no `PRODUCT_BUNDLE_IDENTIFIER` line, unlike `.dev` at `:821` and `.stg` at `:723`); `macos/Runner/Info.plist` uses `$(PRODUCT_BUNDLE_IDENTIFIER)` and `$(PRODUCT_COPYRIGHT)`; built and published by `release.yaml` `build-macos`.
- **Production impact:** The bundle identifier is the app's identity for the sandbox container (`~/Library/Containers/com.example.myApp`), preferences, Keychain (where `flutter_secure_storage` keeps the HF token) and notarization. Shipping v1.0 with the template ID and fixing it later orphans every macOS user's data and token. The About panel shows a 2023 `com.example` copyright. iOS is correctly set (`wtf.rag.offline.sync.offline-sync`, `ios/Runner.xcodeproj/project.pbxproj:376`).
- **Fix:** Set `PRODUCT_BUNDLE_IDENTIFIER = wtf.rag.offline.sync.offline-sync` in the three production build configurations (or in `AppInfo.xcconfig`), update `PRODUCT_COPYRIGHT`, and add a release-workflow check that greps the built `Info.plist` for `com.example`.

### H-5. First launch auto-downloads up to 6.7 GB with no consent, no metered-network or disk-space check, and a hard-coded GPU assumption that selects GPU-only models on CPU-only machines

- **Files:** `lib/ui/views/startup/startup_viewmodel.dart:181-190` (downloads start immediately after tier selection), `:29-31` (device service is a fresh instance, not the locator singleton); `lib/services/device_capability_service.dart:135,155,172,189,206` (`hasGpu: true` on every native platform); `lib/services/model_recommendation_service.dart:142-145` (premium requires `hasGpu`, which is always true); `lib/services/model_config.dart:74,89` (`requiresGpu: true` on the 3n models) — `requiresGpu` is never read anywhere in `lib/`; `getCompatibleInferenceModels` (`:97-115`) checks size/RAM but is unused.
- **Production impact:** A phone on cellular downloads 0.4–6.7 GB without asking (store policies and user expectations both call for consent on large downloads). A 16 GB CPU-only laptop is classified premium because GPU presence is assumed. Storage is only checked coarsely through the tier thresholds; nothing compares `sizeBytes` against free space before starting, and there is no way to pick a smaller tier from the startup screen.
- **Fix:** Show a consent step listing the models and sizes with a "use smaller models" option; gate on non-metered connectivity (or explicit override); compare `sizeBytes` sum against `availableStorageMB`; detect GPU (or default `hasGpu` to false on desktop) and enforce `requiresGpu` in tier selection; inject `DeviceCapabilityService` from the locator so Startup, Settings and ContextualRetrieval agree.

---

## MEDIUM

### M-1. LLM chat sessions are never closed, and concurrent features close each other's sessions *(carried from Round 2 M-13)*
- **Files:** `lib/services/rag_service.dart:382-398,456-473`, `lib/services/query_expansion_service.dart:30-42`, `lib/services/reranking_service.dart:88-98`, `lib/services/contextual_retrieval_service.dart:103-115` — every path calls `createChat` and abandons the chat; repo-wide there is no `chat.close()`/`session.close()`.
- **Plugin facts:** `InferenceModel.session` is a "singleton lane — each `createSession` call overwrites this field with a new session and closes the previous one" (`flutter_gemma_interface.dart:197-199`); `createChat` builds on it; the docs ask callers to "hold the returned chat reference yourself and close it when done" (`:393-394`).
- **Impact:** The last session's KV cache stays resident for the process lifetime, including in the background. If contextual retrieval is enabled and a document is being ingested while the user asks a question, the two `createChat` calls close each other's sessions mid-generation: the ingestion side swallows the failure into an empty context (`contextual_retrieval_service.dart:116-124`), the chat side surfaces "Error: …". Reranking + generation within one query are sequential and therefore safe.
- **Fix:** `close()` chats in `finally`; serialize all LLM use behind one async queue (or use `openChat` for the ingestion side and accept serialized inference); release the session on `AppLifecycleState.paused`.

### M-2. Settings screen has no error handler on the model-status stream and no way to see or fix a download failure
- **Files:** `lib/ui/views/settings/settings_viewmodel.dart:98-100` (`listen((_) => notifyListeners())`, no `onError`); `lib/services/model_management_service.dart:515-524,290,322,655-657,692` (`_statusController.addError` on every download/activation/checksum failure); `lib/ui/views/settings/settings_view.dart:571-650` (`_ModelTile` shows status and a retry icon but never `errorMessage`; no token entry anywhere in Settings).
- **Impact:** Tapping download on a gated model in Settings without a token produces an unhandled stream error (recorded as a crash by `PlatformDispatcher.onError` in release, red error in debug), a red "ERROR" tile with no text, and no path to enter a token — the only token UI is the startup screen (`startup_view.dart:231-234`) and the chat's dead auth catch (see L-1).
- **Fix:** Add `onError` to the Settings subscription; render `model.errorMessage` in the tile; add "Enter Hugging Face token" (and "Clear token") to Settings; prefer state (`errorMessage`/`failureKind`) over stream errors for expected failures.

### M-3. Bootstrap has no error boundary — an initialization failure yields a blank screen with nothing logged
- **Files:** `lib/bootstrap.dart:88-97` (`FlutterGemma.initialize`), `:111` (`initializeSqlite`), `:113-115` (`setupLocator`/dialog setup) all run outside any `try`; `FlutterError.onError` is installed at `:99` (after the plugin init) and `PlatformDispatcher.onError` at `:117` (after the locator); only `runAppFn(await builder())` is guarded (`:128-138`).
- **Impact:** On web, `WasmSqlite3.loadFromUrl` / `IndexedDbFileSystem.open` (`bootstrap_web.dart:11-14`) fail in private browsing, when IndexedDB is blocked, or when the wasm asset 404s under a wrong base href — the user sees a blank page and no crash record is written. Native plugin init failures behave the same.
- **Fix:** Install both error handlers first; wrap initialization in `try/catch`; on failure `runApp` a minimal error screen with the message and a retry/diagnostics action; record the crash.

### M-4. Switching the embedding model silently removes every existing document from retrieval
- **Files:** `lib/services/vector_store.dart:286-294` (rows filtered to the active `embedding_model_id`; legacy `NULL` rows pass through, see L-19); `lib/services/model_management_service.dart:577-601` (`switchEmbeddingModel` re-activates and persists, nothing else); `lib/ui/views/settings/settings_view.dart:126-201` (radio list offers the switch); `lib/ui/views/document_library/*` (library still lists the documents as "Ready").
- **Impact:** Round 2 H-4 prevented cross-space cosine garbage, but the replacement behavior is that all previously ingested documents return zero results after a supported Settings action, with no warning, badge, or re-index action. The user experiences "the app forgot my documents".
- **Fix:** Warn before switching (count of documents that will need re-indexing), add a per-document "re-index" action (the parser/chunker pipeline already exists), and show a badge for documents whose vectors don't match the active embedder.

### M-5. No user control over storage or personal data: models can't be deleted, chat history can't be cleared, crash logs can't be viewed or exported *(partly carried)*
- **Files:** `lib/services/model_management_service.dart` (no delete API); `lib/services/chat_repository.dart:133-135` (`clearHistory` has no caller); `lib/services/logging_service.dart:89-97` (`getCrashLogs`/`clearCrashLogs` have no callers); `lib/l10n/arb/app_en.arb` defines `crashLogsTitle`, `clearCrashLogs`, `noCrashLogs` that nothing uses.
- **Impact:** A user who downloads a 6.5 GB model cannot reclaim the space without uninstalling; a privacy-first chat app offers no "delete my conversation"; production failures remain invisible (crash logs are written to SharedPreferences and never read).
- **Fix:** Add "Delete model", "Clear chat history" and a crash-log viewer/export to Settings; the ARB keys already exist.

### M-6. Semantic recall is bounded by keyword candidates and, without candidates, by the 500 newest rows *(carried from Round 2 M-2)*
- **Files:** `lib/services/vector_store.dart:256-265` (candidate gating), `:312-315` (`LIMIT max(limit*2, 500)` ordered by `created_at DESC`).
- **Impact:** Pure-semantic matches (paraphrase, synonym) in chunks older than the newest 500 are unreachable once the corpus grows; combined with H-1 the gate is a recency-ordered `LIKE` set today. Fine for small libraries; undocumented for larger ones.
- **Fix:** Short term, document the bound and raise the scan cap; medium term, score all rows in the isolate in batches or add an ANN index (e.g. sqlite-vec) — the plugin also ships a vector store abstraction worth evaluating.

### M-7. The max-tokens setting is not bounded by the active model's real context, and the prompt budget uses a chars/4 heuristic although the engine exposes exact counts
- **Files:** `lib/services/rag_settings_service.dart:63,124` (512–8192 for every model); `lib/ui/views/settings/settings_view.dart:383-391` (slider max 8192); `lib/services/model_config.dart:55` (`Gemma3-1B-IT…_ekv4096.litertlm` — a 4096-token KV cache); `lib/services/rag_token_manager.dart:7-10` (`length / 4`); plugin: `flutter_gemma_litertlm-1.6.1/lib/src/litert_lm_engine.dart:40-50` clamps only *upward* to 1024, `InferenceModelSession.sizeInTokens` exists (`flutter_gemma_interface.dart:508`).
- **Impact:** Setting 8192 on the 1B model asks the engine for a context the file doesn't support and budgets prompts up to ~6k tokens; CJK or code content tokenizes at 1–2 chars/token, so even default budgets can overflow the session. Failures surface as native errors or truncated answers.
- **Fix:** Cap the slider at the active model's `maxTokens` (and add a per-model `contextLimit` for files with fixed KV sizes); use `sizeInTokens` for the final budget check or a 2.5–3 chars/token estimate.

### M-8. `Error` subclasses escape `on Exception` handlers in the download, activation and ingestion paths
- **Files:** `lib/services/model_management_service.dart:285,317,497` (`on Exception catch`); `lib/ui/views/document_library/document_library_viewmodel.dart:98`.
- **Impact:** A `StateError`/`TypeError`/`ArgumentError` from the plugin (the plugin throws `StateError` for missing active models and `UnsupportedError` for unsupported backends; C-2's `UnsupportedError` from `dart:io` on web is another instance) bypasses the error bookkeeping: the model stays in `downloading` with no `errorMessage`, the startup screen shows "Downloading … 0.0%" until the user retries, and the library's per-file error dialog is skipped. Worse, `initialize()` memoizes its future (`:166-168`) and `refresh()` has no caller, so an `Error` thrown while initializing poisons every later `initialize()` call: the startup screen's Retry re-awaits the same failed future and cannot recover without restarting the app.
- **Fix:** Catch `Object` at these boundaries, record the error state, and rethrow only what should abort; clear `_initFuture` when `_performInitialize` fails (or have `retry()` call `refresh()`).

### M-9. Checksum pins on `*-litert-preview` repos are brittle, and a transient read error during verification deletes a valid multi-GB file
- **Files:** `lib/services/model_config.dart:70,85` (preview repos), `:47-171` (pinned digests); `lib/services/model_management_service.dart:753-765` (`verifyFileSha256` returns `false` on *any* error), `:685-693` (mismatch → `deleteSync()` + error).
- **Impact:** If Google re-uploads a preview file, high/premium downloads fail closed until an app update, with no in-app fallback. Separately, an I/O hiccup while hashing is indistinguishable from corruption and destroys the download. Integrity checking is the right call; the failure handling is too blunt.
- **Fix:** Distinguish read errors from mismatches (retry/hold instead of delete); allow a remotely-updatable digest list or a "verify from Hugging Face LFS pointer" path; surface a specific message.

### M-10. Main CI never builds a platform target — platform breakage is only detected by the manual release workflow
- **Files:** `.github/workflows/main.yaml:20-25` (format/analyze/test only); `release.yaml` is `workflow_dispatch` only.
- **Impact:** Gradle/Kotlin/AGP bumps, Podfile or CMake changes, and web asset problems (C-1 is an example of a class no unit test catches) reach `main` unnoticed.
- **Fix:** Add `flutter build web --release` (cheap) and `flutter build apk --debug --flavor development` jobs to `main.yaml`; run the release workflow's `verify` job on a schedule.

### M-11. Restoring a saved embedding-model id that no longer exists falls back to an inference model
- **Files:** `lib/services/model_management_service.dart:244-253` (`orElse: () => _models.first`, whose first element is `gemma3-270m`), `:270-277` (activation then throws "Tokenizer URL is required").
- **Impact:** After any catalog rename, startup emits a spurious activation error and marks the 270M model errored — provided that model is downloaded (`:248` gates on status); the inference-side fallback (`:231-235`) has the milder failure of silently activating the 270M model instead of the saved one. Low probability, but it corrupts the startup error flow.
- **Fix:** Fall back to the first model of the matching type, or to `null` and let startup re-select.

---

## LOW

| # | File:Line | Issue | Fix |
|---|---|---|---|
| L-1 | `rag_service.dart:102-203` (`askWithRAG`), `model_management_service.dart:170-173` (`refresh`), `document_management_service.dart:374-439` (`refreshDocument`, `hasDocumentChanged`, `deleteAllDocuments`, `optimizeDatabase`, `cancelIngestion`), `logging_service.dart:89-97`, `chat_repository.dart:133-141`, `rag_settings_service.dart:162`, `contextual_retrieval_service.dart:66-69`, `model_recommendation_service.dart:97-135`, `environment_service.dart:4-6`, `chat_viewmodel.dart:260-268` (`RagService` never throws `AuthenticationRequiredException`) | Dead or unreachable code misleads maintainers; `askWithRAG` duplicates ~120 lines of `_generateStream` (only tests call it) | Delete or wire up deliberately; keep one generation path |
| L-2 | `settings_view.dart` (~30 literals, no l10n import), `startup_viewmodel.dart` (~12), `startup_view.dart` (~7), `document_library_view.dart` (~8 incl. the status labels at `:392-410`), `chat_viewmodel.dart` (~6), `token_input_dialog.dart`, `model_recommendation_service.dart:43-55`; `lib/l10n/arb/app_en.arb` defines 96 keys of which 59 (`settingsTitle`, `queryExpansionTitle`, `hfTokenDialogTitle`, `crashLogsTitle`, …) are read by no view | Spanish locale gets English everywhere except the chat screen and the library's confirmation dialogs; ARB and UI have drifted *(carried)* | Route strings through `AppLocalizations`; add an ARB-unused-key check |
| L-3 | `vector_store.dart:699-701` | `_decodeEmbedding` treats any 6144-byte blob as Float64×768 when called without `targetDimension` (`getChunksForDocument`), so a 1536-dim Float32 vector would be decoded wrongly — latent today (every catalog embedder emits 768 dims) | Store the encoding/dimension explicitly or always pass the dimension |
| L-4 | `startup_viewmodel.dart:29-31`, `settings_viewmodel.dart:20` | `DeviceCapabilityService`/`ModelRecommendationService` constructed directly instead of resolved from the locator (which registers them) | Resolve via locator; one capabilities read per session |
| L-5 | `bootstrap.dart:117-126` | `PlatformDispatcher.onError` returns `true` for everything, so release builds never surface unexpected async errors; combined with M-5 they are invisible | Keep swallowing, but add the crash-log viewer/export and a debug toggle |
| L-6 | `document_management_service.dart:374-390`, `vector_store.dart:506-525` | `refreshDocument` on an unchanged file violates the UNIQUE `content_hash` index (the upsert targets `id` only) and the error-document write in the `catch` throws again — a landmine on a currently dead path; the "same hash" test (`document_management_service_test.dart:450-497`) mocks the store, so the constraint is never exercised | Handle the hash conflict explicitly before wiring refresh to UI |
| L-7 | `bootstrap_web.dart:14-15`, `vector_store.dart:679-682` | Web IndexedDB VFS persists asynchronously; `close()` never calls `flush()`, and the detach lifecycle doesn't fire reliably on tab close | Call `IndexedDbFileSystem.flush()` after writes/before close on web |
| L-8 | `web/manifest.json:6-8`, `web/index.html:33` | PWA description is the Very Good CLI boilerplate; theme colors don't match the app; page title differs from the app name | Fill in real metadata |
| L-9 | `.github/workflows/release.yaml:262-263`, all `uses:` lines | `linuxdeploy` "continuous" AppImages are downloaded unpinned with no checksum; actions pinned by tag, not SHA | Pin releases + verify sha256; pin actions by SHA (Dependabot updates them) |
| L-10 | `android/app/build.gradle.kts:33` (`applicationId = "com.offline_sync.app"`, while `namespace` at `:17` is `wtf.rag.offline.sync.offline_sync`) vs `ios/macos` (`wtf.rag.offline.sync.offline-sync`) vs `linux/CMakeLists.txt:10` (`wtf.rag.offline.sync.offline_sync`) | App identity differs per platform; all are immutable after first store publication | Decide one identity scheme before the first public build |
| L-11 | `android/gradle.properties:1` | `-Xmx8G -XX:MaxMetaspaceSize=4G` exceeds the RAM of smaller CI runners | Lower to `-Xmx4G` or make CI-specific |
| L-12 | `ios/Runner/Info.plist:55-56` | `NSLocalNetworkUsageDescription` declared ("model inference services" — a desktop gRPC leftover) but the iOS app never uses the local network | Remove to avoid an unnecessary prompt/review question |
| L-13 | `environment_service.dart`, flavors | `flavor` is stored and never used; dev/staging builds behave identically to production (e.g. no verbose logging) | Use it, or drop the three-flavor ceremony |
| L-14 | `chat_viewmodel.dart:188,257` | The user turn is persisted before generation; on failure the orphaned question is re-fed as history in later prompts | Persist both turns on completion, or mark failed turns |
| L-15 | `chat_view.dart:41-42,122-127`; `settings_view.dart:83-96,162-175` | Duplicate `SizedBox`; a post-frame callback registered on every build; deprecated `RadioListTile.groupValue/onChanged` suppressed with `ignore` | Tidy; migrate to `RadioGroup` before the deprecation becomes an error |
| L-16 | `document_management_service.dart:97-101,143-149`; `rag_settings_service.dart:164-168` | Size-limit error prints an unrounded double ("12.3456789 MB"); `maxDocumentSizeMB` has no UI | Format; expose or remove the setting |
| L-17 | `inference_model_provider.dart:74-77` | `clearCache()` drops the reference without `close()`; the plugin rebuilds and closes the old model only on the next `getModel()`, so the previous multi-GB model stays loaded until the user chats again | Call `close()` (best-effort) in `clearCache()` |
| L-18 | `test/services/document_management_service_test.dart:167,239,295…`, `test/services/vector_store_test.dart:42-74` | Tests create `*.txt` files and `vectors.db` in the repository root instead of a temp directory (`vectors.db` is gitignored, the text files are not) | Use `Directory.systemTemp.createTemp` (the chat repository test already does, `:32`) |
| L-19 | `vector_store.dart:223-227` (v3 migration adds the column, never backfills), `:291-294` (`embedding_model_id = ? OR embedding_model_id IS NULL`) *(added by the review pass)* | Rows embedded before schema v3 keep `NULL` and are scored against whichever embedder is active; Gecko and EmbeddingGemma are both 768-d, so legacy rows still mix vector spaces — the exact failure Round 2 H-4 set out to prevent. Pre-release data only | Backfill `embedding_model_id` with the active embedder id in the v3 migration (or on first search after upgrade) |

---

## Assessments by category

### Correctness and edge cases
The RAG pipeline's logic is sound where it is exercised by tests, but the three defects that matter most sit exactly where tests can't reach: FTS5 syntax rules (H-1), platform/engine compatibility (C-1) and the web checksum path (C-2). Other correctness gaps: embedder switch (M-4), context-size mismatch (M-7), `Error` vs `Exception` and the poisoned `initialize()` future (M-8), fallback id (M-11), decode heuristic (L-3), legacy-row embedder filter (L-19). Concurrency between the ingestion LLM path and chat (M-1) is the remaining race.

### Security
No hardcoded secrets (re-verified across `lib/`, platform directories, workflows). The Hugging Face token lives in secure storage with iOS `first_unlock` accessibility, the legacy SharedPreferences copy is deleted on migration, the env-var fallback is debug-only, and the token is never logged (the plugin's logging was checked too). SQL is parameterized throughout; FTS input is sanitized (over-cautiously in one direction, see H-1) and `LIKE` wildcards are stripped. Model downloads are HTTPS and integrity-checked. Dependencies: pub reports no advisories. The material security items are privacy posture (H-3) and release-pipeline supply chain hygiene (L-9). Authorization is not applicable (single-user, no server).

### Error handling and input validation
Every UI-triggered async path has a `try/catch` with user feedback, ingestion failures persist an error status, helper LLM calls degrade gracefully with timeouts, file sizes are checked on both ingestion paths, binary files are rejected, and the token dialog validates format. Gaps: the Settings stream (M-2), bootstrap (M-3), `Error` vs `Exception` boundaries (M-8), checksum error vs mismatch (M-9), the fail-closed "path not exposed" branch that is fatal on web (C-2), and the misleading "may still be downloading" wrapper that hides real causes such as C-1 (`inference_model_provider.dart:48-54`).

### Logging and observability
`LoggingService` is level-gated (warning+ in release) and crash handlers write the last 50 crashes to SharedPreferences — which nothing reads (M-5). `dart:developer` `log()` calls are no-ops in release. This is a deliberate no-telemetry posture; the consequence is that production failures are invisible unless a user sends a device. The cheapest closure is a crash-log viewer/export in Settings (ARB keys already exist). Silent fallbacks (H-1's `catch → LIKE`, contextual-retrieval empty context) should at least log at warning level.

### Configuration management
Tunables are centralized in `RagConstants` and `RagSettingsService` (clamped on read and write). Model catalog, URLs and digests are constants in `model_config.dart`. CI signing uses GitHub Secrets and fails closed. Flavors exist but gate nothing (L-13). Platform identity is inconsistent (L-10) and wrong on macOS (H-4). The catalog lacks the one attribute the runtime actually needs — which platforms/engines can run each file (C-1).

### Test coverage on critical paths
368 tests, 97.33% of instrumented lines, analyzer clean. The suite is strong on view models, settings, parsing and the SQL layer. Structural gaps that let both Criticals and two Highs through:
- No test feeds punctuation to `hybridSearch`/`_sanitizeFtsQuery`; the "operator-only" test passes only because the fallback returns nothing (`vector_store_test.dart:195-196`), and the fallback test (`:199-231`) drops the FTS table instead of sending a real question.
- No test asserts that a recommended model is runnable on the platform it is recommended for (C-1); `ModelRecommendationService` tests ignore `platform` and `requiresGpu`.
- No test drives `_verifyDeclaredChecksum` through the production `_resolveInstalledModelPath` with a web-shaped (`blob:`/`opfs://`) path (C-2); every test injects the resolver or the downloader, which also triggers the test-only bypass at `model_management_service.dart:633-641`.
- No test covers checksum-cache persistence across service instances (H-2) or `SettingsViewModel` receiving a stream error (M-2).
- No test covers bootstrap failure paths (M-3); `bootstrap_test.dart` only exercises the happy path with all hooks overridden.
- 125 `coverage:ignore` markers remain (57 start/end regions, 8 single lines, 3 whole files) around plugin call sites, and the gate was lowered to 95%. That is a reasonable unit-test boundary, but there is still no on-device or desktop integration run; `docs/manual_verification_plan.md:638-640` leaves desktop unchecked.

### Performance
Round 2's fixes hold (bounded scans, batched inserts, isolate parsing, streamed hashing, sequential reranking). Remaining risks in order: H-2 (startup hashing, the largest user-visible cost), M-6 (recall bound vs. scan cap), M-1 (resident KV cache), and the 10-way concurrent `generateEmbedding` fan-out during ingestion (`document_management_service.dart:276-324`), which the plugin serializes in its worker anyway (`flutter_gemma_embeddings-2.0.0/lib/src/common_embedding_model.dart:81-82`), so it buys nothing but adds memory pressure. No unbounded loops or N+1 patterns were found; all network calls (downloads) go through the plugin with progress and are the only network dependency.

### Deployment readiness
- **Android:** builds, signs fail-closed, verifies with `apksigner`, R8 + keep rules, monotonic `versionCode`. Blockers before public release: H-1, H-2, H-5; decide H-3. `allowBackup` posture undefined.
- **iOS:** unsigned by design; when signing is added, H-3 (Documents + Application Support in iCloud backup) becomes user-visible immediately.
- **macOS:** builds and now has the right entitlements, but ships `com.example.myApp` (H-4) and cannot run three of four catalog models (C-1). Not shippable.
- **Windows / Linux:** artifacts build; C-1 makes most machines non-functional after first launch. Not shippable.
- **Web:** COI shim + self-hosted runtimes are in place, but C-2 stops every launch at checksum verification. **Not shippable.** Once fixed: low tier only (`.task` via MediaPipe web), inherits H-1, and M-3 is most likely to bite here.
- **CI:** release gated on analyze + test; main gated on 95% coverage + spell check — and `main` is currently red on the spell-check job at the audited commit (five unknown words in a plan document; see Verification status); no build smoke job (M-10); pinned third-party downloads missing (L-9).
- **Data migrations:** `PRAGMA user_version` = 3 with gated migrations (dedup + `embedding_model_id`); the pattern is sound and tested (`vector_store_test.dart:115-122,299-372`), but the v3 step leaves legacy rows untagged (L-19).
- **Health checks / graceful shutdown / Dockerfile:** not applicable (client-only). The DB is closed on lifecycle detach; sessions are not (M-1).

## Positive findings (verified, no action)

- Parameterized SQL everywhere, including generated `IN (...)` placeholders; transactions with rollback on batch insert and deletes, tested.
- Duplicate-ingestion defense in depth: SHA-256 dedup + in-flight hash set + UNIQUE index + migration that dedups existing rows.
- Checksum verification is implemented for all 8 models and fails closed on native (on web the same fail-closed logic is what breaks first launch — C-2); `foreground: true` on Android downloads with a configured notification and a once-only permission request.
- Typed download-failure classification with actionable gated-repo guidance, repo link derivation, and copy-to-clipboard — well tested.
- Settings sliders persist on change-end with stale-drag protection; `RagSettingsService` clamps on read and write.
- `InferenceModelProvider` memoizes the in-flight future; the plugin's `createModel` closes and rebuilds on identity/param change, so model switching is correct (only deferred, L-17).
- Web/native split via conditional imports is consistent (sqlite, paths, bootstrap); the MediaPipe bundle is self-hosted.
- The Round 2 remediation was real: 27 of its 35 items verified fixed in code (L-12 partially); the 7 carried items are listed in "Status of the Round 2 audit".

## Suggested remediation order

1. **Before any desktop or web artifact is published:** C-1 (platform-aware catalog/tiering; or drop desktop from the release matrix), C-2 (`kIsWeb` guard around on-disk checksum verification, then a real browser run; or drop web from the matrix), H-4 (macOS identity).
2. **Before the Android beta (hours to a day):** H-1 (tokenize + quote FTS terms, stop gating on fallback candidates, add punctuation tests), H-2 (persist checksum verification), H-5 (consent + metered check + GPU/`requiresGpu` enforcement), M-2 (Settings error handling + token entry), M-8 (`catch Object` at boundaries).
3. **Policy decision before first public build:** H-3 (backup exclusion on iOS/Android; state it in the privacy copy).
4. **Next iteration:** M-1 (close sessions, serialize LLM use), M-3 (bootstrap error boundary), M-4 (re-index UX), M-5 (delete model / clear history / crash logs), M-7 (per-model context cap, `sizeInTokens`), M-9 (verification error handling), M-10 (CI build smoke), M-11, M-6 (document or replace the recall bound).
5. **Hygiene batch:** the Low table; L-1 and L-2 first.

---

## Appendix A — Verification artifacts

### A.1 FTS5 sanitizer probe

Standalone Dart script using the project's `sqlite3` dependency (bundled SQLite 3.53.4, same build hooks as the app), reproducing `VectorStore._sanitizeFtsQuery` and the `vectors_fts` external-content table:

```text
OK    "refund policy"                   -> MATCH "refund policy"                 -> [a]
FAIL  "What is the refund policy?"      -> MATCH "What is the refund policy?"    -> fts5: syntax error near "?"
FAIL  "What's the shipping time"        -> MATCH "What's the shipping time"      -> fts5: syntax error near "'"
FAIL  "returns, refunds and shipping"   -> MATCH "returns, refunds shipping"     -> fts5: syntax error near ","
FAIL  "How long does shipping take!"    -> MATCH "How long does shipping take!"  -> fts5: syntax error near "!"
FAIL  "C++ pointers"                    -> MATCH "C++ pointers"                  -> fts5: syntax error near "+"
FAIL  "email me at a.b@c.com"           -> MATCH "email me at a.b@c.com"         -> fts5: syntax error near "."
OK    "This is not working"             -> MATCH "This is working"               -> []   (operator regex deleted "not")
FAIL  ""                                -> MATCH ""                              -> fts5: syntax error near ""
```

Every `FAIL` row is caught by `_fts5Search`'s `on Exception` and silently routed to `_fallbackKeywordSearch` (`SqliteException implements Exception`, `sqlite3-3.5.2/lib/src/exception.dart:9`). Re-run during the review pass with identical results.

### A.2 SHA-256 throughput probe

`package:crypto` chunked SHA-256 over 256 MB of in-memory data, Dart 3.13.2 JIT, x64 desktop:

```text
sha256 throughput: 148 MB/s
  0.58 GB (Gemma 3 1B)             ->  4.0 s
  0.76 GB (1B + EmbeddingGemma)    ->  5.3 s
  3.3  GB (3n E2B + embedding)     -> 22.9 s
  6.7  GB (3n E4B + embedding)     -> 46.4 s
```

These are lower bounds for mobile devices (AOT on ARM, slower flash, thermal limits). Review re-run: 146 MB/s → 4.0 / 5.3 / 23.5 / 48.0 s for the same four sizes.

### A.3 Commands run

```text
flutter --version                       # 3.47.2 / Dart 3.13.2
flutter analyze                         # No issues found
flutter test --coverage --reporter expanded   # 368 passed
flutter pub get                         # no advisories
flutter pub outdated                    # 10 constrained majors (get_it 9, xml 7, syncfusion 34, flex_seed_scheme 5, ...)
git status --short --untracked-files=all       # clean after cleanup

# Review pass (same day): flutter analyze, flutter test --coverage (368 passed, 97.33%),
# flutter pub outdated, and the A.1 / A.2 / A.4 probes via `dart run build/probe/*.dart`
# (build/ is gitignored; the probe directory was deleted afterwards).
```

### A.4 Web path-matching probe (C-2)

`ModelManagementService._resolveInstalledModelPath` keeps a `getModelFilePaths` entry only if `path.split(RegExp(r'[\/\\]')).last == definition.fileName`. Applied to the three URL shapes the plugin can register for `gemma3-270m-it-q8.task`:

```text
blob:https://x.github.io/6f1c0a2e-uuid     -> 6f1c0a2e-uuid          match=false  (Cache API path: no entry -> "path not exposed" -> error)
opfs://gemma3-270m-it-q8.task              -> gemma3-270m-it-q8.task match=true   (OPFS path: File('opfs://...') -> UnsupportedError on web)
C:\Users\a\gemma3-270m-it-q8.task          -> gemma3-270m-it-q8.task match=true   (native: works)
```

## Appendix B — Where the Round 2 "ready" verdicts changed

Round 2 declared Windows/Linux desktop "ready" and web "ready with caveats". Neither verdict accounted for the engine/file-type matrix (C-1), the macOS identity (H-4) or the web checksum path (C-2); all three are configuration/code facts that were already true at Round 2, not regressions, and none of the three rounds has executed a desktop or web build (`docs/manual_verification_plan.md:630-643`, all unchecked). Everything else in this report is either new analysis (H-1, H-2's ineffective cache, H-3's backup semantics, H-5, L-19) or explicitly carried.

*Generated by production audit 2026-09-04 against `main` @ `27366e5`, then re-verified line by line the same day (review pass). Full analyzer and test suite were run twice; the probe scripts were executed and removed; no application code was modified.*
