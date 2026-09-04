# Production Audit Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every actionable finding in `docs/production-audit.md` so the offline RAG app has correct model/platform behavior, durable integrity checks, safe lifecycle/error handling, user data controls, localized UI, and release/CI configuration that matches the supported targets.

**Architecture:** Work is split into six independently testable subsystem tasks. Model selection and download policy establish the runtime contract first; retrieval and lifecycle fixes consume that contract; Settings/data controls expose the resulting state; platform/bootstrap/release configuration closes deployment gaps; the final hygiene task removes dead paths, localizes remaining UI, and isolates tests. Existing public service constructor APIs remain compatible, with optional injected seams added where tests need deterministic behavior.

**Tech Stack:** Flutter 3.47/Dart 3.13, Stacked MVVM, get_it, flutter_gemma 1.7.0, sqlite3/FTS5, SharedPreferences, Flutter platform channels, GitHub Actions.

**Spec:** `docs/production-audit.md`

## Global Constraints

- Preserve the existing Flutter/Dart floors and dependency versions unless a task explicitly adds a required direct platform capability.
- Keep SQL parameterized; user text must never be interpolated into SQL or FTS expressions.
- Keep the app offline-first; model downloads remain HTTPS-only and no telemetry is introduced.
- Preserve existing service constructor signatures and test seams unless an optional parameter is added for deterministic tests.
- `flutter analyze` must finish with 0 errors, 0 warnings, and 0 infos.
- The full Flutter test suite must remain green after every task.
- User-visible strings added or changed in UI belong in both `app_en.arb` and `app_es.arb`; generated localization files remain ignored build artifacts.
- Expected download/activation failures are represented in model state and handled by subscribers; they must not become unhandled stream errors.

## Pre-flight task/interface scan

| Tasks | Shared output/consumer | Finding and ruling |
|---|---|---|
| 1 → 2 | Task 1 model definitions and compatibility checks are consumed by Task 2 checksum/initialization logic | Compatible model ids and file types remain stable; Task 2 verifies only catalog entries accepted by Task 1. No contradiction. |
| 1 → 3 | Task 1 active embedding/inference ids are consumed by Task 3 vector filtering and token budgeting | Task 3 must use the active ids and model context limits exposed by Task 1; no cross-task fallback to an unrelated model. |
| 1 → 4 | Task 1 download policy/status is consumed by Settings and Task 4 data controls | Settings shows the same status/error state as startup; no duplicate policy decisions. |
| 2 → 4 | Task 2 initialization/error state is observed by Settings | Task 2 clears failed memoized futures and emits state; Task 4 renders that state rather than relying on stream error events. |
| 3 → 4 | Task 3 model/session lifecycle is used by Settings model switching and cleanup | Model cache clearing remains best-effort and awaitable where needed; Task 4 does not bypass the provider. |
| 4 → 5 | Task 4 user-facing backup/privacy behavior is documented by release/platform config | Android/iOS exclusion is the implementation of the documented no-backup posture; no conflicting privacy claim remains. |
| 4 → 6 | Task 4 adds localization keys and UI entry points; Task 6 removes remaining literal/dead UI paths | Task 6 reuses Task 4 keys and does not duplicate controls. |
| 1 | Model catalog, recommendation, startup, and download policy tests match the files changed by this task | Internally consistent; tests cover platform × tier and policy rejection. |
| 2 | Model manager, checksum persistence, initialization, and error tests match the files changed by this task | Internally consistent; tests cover cold-start cache hits, read errors, mismatches, web paths, and retry. |
| 3 | Vector store, RAG services, provider, and chat history tests match the files changed by this task | Internally consistent; tests cover punctuation, semantic candidates, close-on-error, model dimensions, and failed turns. |
| 4 | Settings/data services, views, localization, and native backup files match the controls changed by this task | Internally consistent; tests cover stream errors, token actions, data cleanup, and embedder mismatch state. |
| 5 | Bootstrap, native platform files, web metadata, CI workflows, and release checks match deployment changes | Config-only checks use YAML/XML/plist/build inspection rather than vacuous unit assertions. |
| 6 | Dead-code removal, localization completion, UI cleanup, and temp-file test fixtures match the final hygiene scope | Internally consistent; test updates preserve behavior and eliminate repository-root writes. |

### Task 1: Platform-aware model catalog and guarded first-run downloads (C-1, H-5, M-11, L-4)

**Files:**
- Modify: `lib/services/model_config.dart`, `lib/services/model_recommendation_service.dart`, `lib/services/device_capability_service.dart`, `lib/services/model_management_service.dart`, `lib/ui/views/startup/startup_viewmodel.dart`, `lib/app/app.locator.dart`
- Create or modify: download-policy seam/service and startup consent UI using the existing dialog setup
- Test: model recommendation, device capability, model management, and startup view-model tests

**Interfaces:**
- `ModelDefinition` exposes file type/platform compatibility and existing model metadata.
- `ModelRecommendationService.getRecommendedModels(DeviceCapabilities)` returns only runnable models.
- Download policy receives the selected model pair and capabilities, and returns an explicit allow/deny result with a user-facing reason.

- [ ] Add a platform/file-type matrix: desktop inference recommendations are `.litertlm`; web/mobile recommendations are `.task` only where the registered engine supports them; embedding choices remain compatible with the active platform. Filter compatible models before tier selection and use a valid same-type fallback when a saved id is missing.
- [ ] Make native desktop GPU detection conservative (`false` unless positively detected), enforce `requiresGpu`, and inject the locator singletons into Startup and Settings rather than constructing duplicate services.
- [ ] Add download-policy checks for aggregate model bytes versus free storage, metered/unknown connectivity, and explicit user consent. The consent dialog lists both model names/sizes and offers a smaller compatible tier; denial leaves models untouched and gives retry a deterministic path.
- [ ] Refuse incompatible model download/activation with a clear model-specific error and state update. Add tests for every supported platform × tier, GPU rejection, insufficient space, metered consent, and missing catalog ids.
- [ ] Run focused tests, `flutter analyze`, then the full suite and commit with a Conventional Commit message.

### Task 2: Durable checksum verification and recoverable model initialization (C-2, H-2, M-8, M-9)

**Files:**
- Modify: `lib/services/model_management_service.dart`, related platform-conditional checksum helpers, `lib/ui/views/startup/startup_viewmodel.dart`
- Test: `test/services/model_management_service_test.dart`, startup tests, and a new web-shaped resolver test

**Interfaces:**
- Persisted verification records contain model id/path, size, modification marker, and expected digest.
- Checksum verification distinguishes `verified`, `mismatch`, `unavailable-on-web`, and `read-error`; only a confirmed mismatch may remove a file.
- `ModelManagementService.initialize()` retries after a failed initialization future.

- [ ] On web, treat plugin-managed `blob:`/Cache API model paths as plugin-verified and never pass them to `dart:io`; retain fail-closed behavior for native unresolved paths. Cover a resolver returning a `blob:` URL.
- [ ] Persist successful native verification metadata in SharedPreferences, use it on unchanged cold starts, and run expensive hashing in `compute()` or an equivalent background isolate. Keep immediate post-download verification.
- [ ] Preserve valid files on read/I/O errors, report a retryable verification error, and delete only confirmed digest mismatches. Catch `Object` at download and activation boundaries and record the resulting model error state.
- [ ] Clear the memoized initialization future on failure so Startup Retry can recover; keep expected stream errors from becoming unhandled errors.
- [ ] Run focused model/startup tests, `flutter analyze`, and the full suite, then commit.

### Task 3: Retrieval correctness, token budgeting, and LLM resource lifecycle (H-1, M-1, M-6, M-7, L-3, L-6, L-7, L-14, L-17, L-19)

**Files:**
- Modify: `lib/services/vector_store.dart`, `rag_service.dart`, `query_expansion_service.dart`, `reranking_service.dart`, `contextual_retrieval_service.dart`, `rag_token_manager.dart`, `inference_model_provider.dart`, `chat_repository.dart`, `lib/ui/views/chat/chat_viewmodel.dart`
- Test: corresponding service/view-model tests, including migration, punctuation, lifecycle, and failed-generation cases

**Interfaces:**
- FTS sanitizer returns quoted Unicode word tokens or an empty query; fallback logging is explicit and semantic search is not gated by fallback candidates.
- Embedding decoding receives an explicit dimension/encoding, and v3 migration assigns legacy rows to the active embedder rather than allowing `NULL` rows into every search.
- LLM operations close chats in `finally` and pass through one serialized inference lane.

- [ ] Replace the FTS sanitizer with Unicode word tokenization and per-token quoting; skip FTS for empty input, log fallback warnings, and score semantic candidates independently of a failed keyword query. Add real punctuation/apostrophe/empty-query tests.
- [ ] Remove the arbitrary newest-row semantic cap or replace it with documented batch scanning that covers the complete corpus within controlled memory; keep all dynamic SQL parameterized.
- [ ] Carry exact model context limits through settings and prompt budgeting, clamp persisted/current max tokens per active model, and use tokenizer/session token counts when available with a conservative fallback estimate.
- [ ] Serialize all LLM calls, close every chat in `finally`, release the provider model on cache clear, and close sessions when the app is paused. Ensure a failed generation is marked/reconciled so an orphaned user turn is not re-fed.
- [ ] Make embedding decoding dimension-safe, handle unchanged refresh hash conflicts without a second failing write, flush web IndexedDB after writes/before close, and backfill legacy v3 embedding ids.
- [ ] Run focused retrieval/lifecycle tests, `flutter analyze`, and the full suite, then commit.

### Task 4: Settings recovery, data controls, embedder UX, and backup posture (H-3, M-2, M-4, M-5, L-5, L-16)

**Files:**
- Modify: `lib/ui/views/settings/settings_view.dart`, `settings_viewmodel.dart`, `lib/services/model_management_service.dart`, `chat_repository.dart`, `logging_service.dart`, document-library view/model files, `lib/l10n/arb/app_en.arb`, `lib/l10n/arb/app_es.arb`
- Modify: `android/app/src/main/AndroidManifest.xml`, iOS/macOS native app delegates or storage channel, `lib/services/vector_store_path_native.dart`, `web/index.html`
- Test: Settings, model management, data-control, and localization/widget tests

**Interfaces:**
- Settings subscribes with an `onError` handler but renders expected failures from `ModelInfo.errorMessage`/failure kind.
- Model cleanup exposes delete-model; chat cleanup exposes clear-history; logging exposes read/clear/exportable crash entries.
- A platform storage helper marks the database and model directories excluded from OS backup.

- [ ] Add token entry and clear-token actions to Settings, show model failure text and retry state, and ensure stream errors do not escape the view model.
- [ ] Add confirmation-backed delete-model, clear-chat-history, and crash-log viewer/export/clear controls. Keep multi-gigabyte deletion best-effort and refresh model state afterward.
- [ ] Warn before embedding-model switches with the count of documents requiring re-indexing; expose mismatch badges and a per-document re-index action through the existing ingestion pipeline.
- [ ] Exclude the app database and model storage from iCloud/Finder and Android backup, and update privacy copy to state the resulting behavior. Add Android manifest backup policy and the smallest native storage-exclusion channel needed by iOS/macOS.
- [ ] Format document-size errors and expose the configured size limit in Settings. Add/translate all new strings in both locales and test the actions.
- [ ] Run focused Settings/data tests, `flutter analyze`, and the full suite, then commit.

### Task 5: Bootstrap resilience, platform identity, metadata, and CI/release gates (H-4, M-3, M-10, L-8, L-9, L-10, L-11, L-12, L-13)

**Files:**
- Modify: `lib/bootstrap.dart`, `lib/services/environment_service.dart`, `macos/Runner/Configs/AppInfo.xcconfig`, macOS project configs, `ios/Runner/Info.plist`, `android/gradle.properties`, `web/manifest.json`, `web/index.html`, `.github/workflows/main.yaml`, `.github/workflows/release.yaml`, `.github/cspell.json`, relevant platform identity files
- Test/verify: bootstrap tests plus YAML/plist/XML checks and Flutter web/APK builds where available

**Interfaces:**
- Bootstrap installs crash handlers before initialization and renders a minimal retryable failure app after initialization errors.
- Production macOS uses `wtf.rag.offline.sync.offline-sync` and a real copyright string; all platform ids follow the pre-publication identity decision.
- Main CI includes web release and Android debug smoke builds; release verification rejects template identities and unpinned/unverified packaging tools.

- [ ] Install both error handlers before plugin/SQLite/locator setup, wrap initialization in a catch boundary, record failures, and run a localized retry/diagnostics screen instead of leaving a blank app.
- [ ] Make flavor behavior meaningful for logging/configuration or remove unused flavor state; preserve the three existing entrypoints while making production distinguishable.
- [ ] Correct macOS production bundle identity/copyright, remove the unused iOS local-network prompt, align platform identities, and lower Gradle heap defaults for smaller runners.
- [ ] Replace boilerplate PWA metadata and add the required cspell technical terms, pin Linux packaging downloads with checksums, and pin/maintain GitHub Actions references according to repository policy.
- [ ] Add main-workflow web and Android smoke jobs, schedule release verification, and add a built-metadata check for `com.example`.
- [ ] Run config validation and available target builds, bootstrap tests, `flutter analyze`, and the full suite, then commit.

### Task 6: Dead-path removal, complete localization, UI cleanup, and hermetic tests (L-1, L-2, L-15, L-18)

**Files:**
- Modify/delete only the dead methods and call sites identified in `rag_service.dart`, `model_management_service.dart`, `document_management_service.dart`, `logging_service.dart`, `chat_repository.dart`, `rag_settings_service.dart`, `contextual_retrieval_service.dart`, `model_recommendation_service.dart`, `environment_service.dart`, and chat/startup/settings/document-library/token UI
- Modify: `test/services/document_management_service_test.dart`, `test/services/vector_store_test.dart`, and any affected test helpers
- Add: a deterministic ARB-unused-key check under the repository’s existing validation scripts

**Interfaces:**
- One production generation path remains; removed APIs are not referenced by application code or tests unless the test is updated to the supported path.
- Every user-visible string in the touched screens is obtained from `AppLocalizations`; the ARB check reports unused English keys.
- Test-created files live under per-test temporary directories and are removed in teardown.

- [ ] Delete or deliberately wire the listed dead paths, including the duplicate `askWithRAG` generation implementation, without changing the active production flow.
- [ ] Route remaining startup/settings/library/chat/dialog/recommendation strings through localization, add Spanish translations, and make the ARB-unused-key check fail on drift.
- [ ] Remove duplicate layout widgets and build-time post-frame registration, and migrate suppressed radio APIs to the current Flutter API where supported.
- [ ] Move document/vector test fixtures to `Directory.systemTemp.createTemp`, preserve cleanup in teardown, and prove no repository-root fixture is created.
- [ ] Run the targeted hygiene tests, the ARB check, `flutter analyze`, and the full suite, then commit.

## Completion gate

- [ ] All six task commits have passed their task-scoped review.
- [ ] `flutter analyze` reports 0 issues and `flutter test --coverage` passes the complete suite.
- [ ] Web release build and Android debug smoke build pass locally or have an explicit environment limitation recorded; workflow syntax and release identity checks pass.
- [ ] A final whole-branch review confirms every C/H/M/L item from `docs/production-audit.md` is fixed or explicitly evidenced as a platform limitation, with no unreviewed Critical/Important findings.
