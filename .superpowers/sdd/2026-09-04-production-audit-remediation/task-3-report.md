# Task 3 Production Audit Remediation Report

## Scope

Fix round 1 was performed in the `production-audit-fixes` worktree from
`804d310`. The work stayed within Task 3 and preserved the already-correct
H-1, M-6, L-6, and L-19 behavior.

## Findings fixed

- **M-1/L-17:** `InferenceModelProvider` now uses one serialized operation lane
  for model loads, chat creation/closure, cache invalidation, and model
  release. Cache generations invalidate in-flight loads; a stale loaded model
  is closed and never installed. Release awaits a lane barrier, so lifecycle
  pause/settings changes cannot close a model during an active serialized chat.
- **M-7:** `RagTokenManager.buildPromptWithinBudget` builds the complete prompt,
  counts it through a supplied exact tokenizer seam, and iteratively removes
  history/context until it fits the active model prompt budget. It then
  truncates the query only as a final fallback. Oversized history entries are
  skipped rather than forced into the prompt. `RagService` uses this path for
  both buffered and streaming generation and logs the final count before
  adding the query.
- **L-3:** Vector decoding requires explicit encoding and dimension. Migration
  validates legacy JSON dimensions and marks legacy base64 rows as
  `unknown`/dimension `0` when the original encoding cannot be proved. Such
  rows are skipped for semantic decoding instead of being guessed as Float32.
- **L-7:** Vector persistence flushes are serialized. Chat writes and terminal
  state updates await the vector-store flush seam. Vector-store shutdown awaits
  queued flushes before closing SQLite and then closes the web persistence VFS.
- **L-14:** User turns are inserted as pending with a stable SQLite row ID.
  Completion clears pending; failures/cancellation clear pending and mark the
  row failed. Startup reconciliation converts unfinished pending user turns to
  failed, and failed turns are excluded from generated history.

## Regression coverage

- Provider serialization, release ordering, and stale-load discard:
  `test/services/inference_model_provider_test.dart`
- Exact final prompt budgeting and oversized-newest history handling:
  `test/services/rag_token_manager_test.dart`
- Explicit embedding metadata and Float64 legacy quarantine:
  `test/services/vector_store_test.dart`
- Pending reconciliation and stable-ID updates, including duplicate turns:
  `test/services/chat_repository_test.dart`
- No-completion stream handling and terminal pending state:
  `test/ui/views/chat/chat_viewmodel_test.dart`
- Updated lifecycle/chat view fixtures for async close and terminal callbacks:
  `test/app/main_app_test.dart`, `test/ui/views/chat/chat_view_test.dart`, and
  `test/helpers/test_helpers.dart`

## Production files changed

- `lib/app/main_app.dart`
- `lib/bootstrap_web.dart`
- `lib/services/chat_repository.dart`
- `lib/services/contextual_retrieval_service.dart`
- `lib/services/inference_model_provider.dart`
- `lib/services/query_expansion_service.dart`
- `lib/services/rag_service.dart`
- `lib/services/rag_token_manager.dart`
- `lib/services/reranking_service.dart`
- `lib/services/vector_store.dart`
- `lib/services/vector_store_persistence_stub.dart`
- `lib/services/vector_store_persistence_web.dart`
- `lib/ui/views/chat/chat_viewmodel.dart`

## Verification

- Focused Task 3 lifecycle, RAG, vector, repository, app, and chat UI suites
  passed; the authoritative post-hardening full-suite result is recorded below.
- Full suite: `flutter test --reporter compact` — **445 tests passed**.
- Static analysis: `flutter analyze` — **No issues found**.
- Web build: `flutter build web --no-pub -t lib/main_production.dart` —
  **built successfully** (`build/web`). The command emitted existing third-party
  Wasm dry-run incompatibilities and a Cupertino font warning; these did not
  prevent compilation.
- `git diff --check` — no whitespace errors.
- Flutter-generated Linux, macOS, and Windows registrants were restored after
  verification. The macOS and Windows connectivity registrations changed in
  this round and are included in the commit.

## Review notes and residuals

- All production `InferenceChat` creation sites remain behind the provider
  serialization seam.
- H-1 Unicode/FTS fallback behavior, M-6 full semantic corpus scanning,
  L-6 refresh/hash behavior, and L-19 active embedder backfill/filtering were
  not changed by this round.
- Web IndexedDB ordering is compile-checked and routed through the flush/close
  seam; this environment does not provide a browser-backed persistence test.
- Native model generation and cancellation depend on the installed
  `flutter_gemma` runtime and were covered here through mockable lifecycle
  seams, not a device run.

## Fix round 2: L-7 review remediation

This round was limited to the remaining L-7 review issue. On `924f6c5`,
`_schedulePersistenceFlush` converted each flush failure into a successful
`_persistenceLane` future, so `flush()` and `close()` could not observe an
IndexedDB failure. `AppLifecycleListener.onDetach` also called the async
`VectorStore.close()` through `unawaited`; Flutter's `onDetach` callback is
synchronous and cannot await a future.

The vector store now keeps a normalized serialization barrier for subsequent
flushes and separately retains the latest actual flush future. `flush()` and
`close()` therefore propagate the actual failure, while a later scheduled
flush can retry after the failed operation. `close()` still flushes before
closing SQLite and then awaits the platform persistence close.

Graceful exit is wired through Flutter's awaitable `onExitRequested` callback,
which awaits the complete vector-store close and cancels exit after reporting
a failure. The synchronous detach fallback explicitly observes and reports
close failures rather than discarding the future.

Regression coverage:

- `test/services/vector_store_test.dart`: injected persistence failure is
  propagated by `flush()`, and the next scheduled flush succeeds.
- `test/app/main_app_test.dart`: app exit remains pending until the mocked
  vector-store close future completes.

Round 2 verification:

- Red/green focused tests: both new tests first failed for the missing seam /
  missing exit close, then passed after the implementation.
- `flutter test test/services/vector_store_test.dart test/app/main_app_test.dart
  --reporter expanded`: **32 tests passed**.
- `flutter test --reporter compact`: **447 tests passed**.
- `flutter analyze`: **No issues found**.
- `flutter build web --no-pub -t lib/main_production.dart`: **built
  successfully** and produced `build/web`.
- `git diff --check`: no whitespace errors.

Residuals: this environment has no browser-backed IndexedDB runtime test, so
the web persistence path is compile/build verified and failure propagation is
covered through the injected persistence seam. Flutter's synchronous detach
callback cannot provide an awaitable completion contract; graceful exit uses
the awaitable exit-request path, while detach explicitly observes failures.

## Commit

This report is included in the fix-round commit for the verified changes.
