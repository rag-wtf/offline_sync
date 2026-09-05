# Task 3 Production Audit Remediation Report

## Scope

Task 3 implementation from the production audit remediation brief, based on
commit `74103c1`. The scope was limited to retrieval safety and recall,
embedding metadata/migrations, model context budgeting and lifecycle,
serialized LLM chat use, refresh/persistence safety, and failed chat-turn
handling.

## Findings mapped

- **H-1** — Replaced ad-hoc FTS sanitization with Unicode word extraction and
  quoted FTS phrases. Empty-token queries skip FTS safely; FTS failures log a
  warning and use parameterized LIKE fallback. Semantic retrieval is no longer
  gated by keyword candidates.
- **M-1** — Centralized all application `InferenceChat` creation through a
  serialized provider lane. Every chat is closed in `finally`, including when
  generation fails; contextual retrieval, expansion, reranking, and RAG use
  the shared lifecycle.
- **M-6** — Removed the newest-row semantic cap and keyword candidate gate.
  Semantic search scans the complete eligible corpus in parameterized batches,
  while keyword results only affect blended ranking.
- **M-7** — Added model-specific context limits, clamps for persisted and
  newly selected token settings, conservative Unicode token estimation, and
  exact session token counting when exposed by the plugin.
- **L-3** — Added explicit `float32`/dimension metadata for stored embeddings
  and removed byte-length-based Float64 inference.
- **L-6** — Refresh now hashes the source before re-ingestion and returns the
  existing document when unchanged, avoiding a unique-hash conflict/error
  record.
- **L-7** — Added web IndexedDB flush plumbing and flushes after vector/chat
  writes and before database close is scheduled.
- **L-14** — Failed persisted user turns are marked explicitly and excluded
  from subsequent generation history, preventing failed prompts from being
  silently re-fed.
- **L-17** — Model cache clearing and application pause now release loaded
  inference models through their close lifecycle.
- **L-19** — Bumped the vector schema, backfilled legacy NULL embedder IDs to
  the active embedder, and restricted semantic search to the active embedder
  corpus.

## Files changed

Production code:

- `lib/services/vector_store.dart`
- `lib/services/vector_store_persistence_stub.dart`
- `lib/services/vector_store_persistence_web.dart`
- `lib/bootstrap_web.dart`
- `lib/services/inference_model_provider.dart`
- `lib/services/model_config.dart`
- `lib/services/rag_settings_service.dart`
- `lib/services/rag_token_manager.dart`
- `lib/services/rag_service.dart`
- `lib/services/query_expansion_service.dart`
- `lib/services/reranking_service.dart`
- `lib/services/contextual_retrieval_service.dart`
- `lib/services/document_management_service.dart`
- `lib/services/chat_repository.dart`
- `lib/ui/views/chat/chat_viewmodel.dart`
- `lib/app/main_app.dart`
- `lib/ui/views/settings/settings_view.dart`
- `lib/ui/views/settings/settings_viewmodel.dart`

Tests:

- `test/services/vector_store_test.dart`
- `test/services/chat_repository_test.dart`
- `test/services/document_management_service_test.dart`
- `test/services/inference_model_provider_test.dart`
- `test/services/rag_settings_service_test.dart`
- `test/services/rag_token_manager_test.dart`
- `test/ui/views/chat/chat_viewmodel_test.dart`
- `test/app/main_app_test.dart`
- `test/helpers/test_helpers.dart`

## Commits

- `94fc016` — `fix: remediate production audit task 3 findings`
- This report is committed separately after recording the implementation hash.

## Verification

- Focused Task 3 service/UI suites: passed.
- Full suite: `flutter test --reporter compact` — **437 tests passed**.
- Static analysis: `flutter analyze` — **No issues found**.
- Web build: `flutter build web --no-pub -t lib/main_production.dart` —
  **built successfully**.
- `git diff --check` — no whitespace errors.
- Flutter-generated Linux, macOS, and Windows registrant changes were restored
  before committing.

## Review notes

- Reviewed all direct `InferenceChat` creation sites and routed them through
  `InferenceModelProvider.withSerializedChat`.
- Reviewed schema migration ordering from the base schema through versions 3,
  4, and 5, including legacy NULL embedder IDs and pre-existing chat tables.
- Confirmed SQL values are parameterized for query terms, document filters,
  hashes, and migration backfills.
- Kept refresh, chat persistence, and lifecycle changes local to their existing
  service boundaries; no unrelated audit task area was changed.

## Residuals

- The default `flutter build web --no-pub` target is not applicable because the
  repository has flavor entrypoints rather than `lib/main.dart`; the
  production entrypoint build was used instead.
- The successful web build reports existing third-party Wasm dry-run
  incompatibility warnings and a Cupertino font asset warning. They do not
  prevent compilation and are outside Task 3 application code.
- IndexedDB flush behavior is compile-checked through the web build; the test
  suite does not run a browser-backed persistence integration test.
