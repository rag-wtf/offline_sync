# Task 4 Fix Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct Task 4's merged code so model identity, retrieval consistency, reindex durability, settings recovery, privacy controls, and compilation are production-safe.

**Architecture:** Keep the existing services and public APIs, adding only optional identity/source seams. A shared embedding-operation lane serializes model switching with ingestion and query embedding/search. SQLite documents retain optional source bytes, and all retrieval uses complete documents whose document and vector identities match the pinned active embedder.

**Tech Stack:** Flutter/Dart, sqlite3, Stacked MVVM, SharedPreferences, platform channels, Flutter widget/service tests.

**Spec:** `.superpowers/sdd/2026-09-04-production-audit-remediation/task-4-brief.md` plus the Task 4 fix-round findings in the user request.

## Global Constraints

- Preserve valid Task 3 behavior and existing public API compatibility.
- No telemetry or new network behavior.
- Localized user-visible strings must exist in both English and Spanish ARB files.
- Generated plugin registrants must remain restored/generated; do not hand-edit them.
- Verify with focused tests, `flutter test --coverage`, `flutter analyze`, web release build, and `git diff --check`.

---

### Task 1: Compile and baseline contracts

**Files:** `lib/models/document.dart`, `lib/services/model_management_service.dart`, affected tests.

- [ ] Confirm the single `Document` declaration/constructor/field/JSON key, single model log helper, single `fileName` argument, and single `deleteModel` implementation.
- [ ] Run `flutter analyze` and the focused affected tests to establish current failures.
- [ ] Preserve the existing corrected declarations and fix only compatibility failures exposed by the current tree.

### Task 2: Pin embedding identity across writes, switches, and queries

**Files:** `lib/services/rag_settings_service.dart`, `lib/services/document_management_service.dart`, `lib/services/model_management_service.dart`, `lib/services/rag_service.dart`, `lib/services/query_expansion_service.dart`, `lib/services/vector_store.dart`; service tests.

- [ ] Add a serialized `runWithEmbeddingModel` seam that validates the expected active ID and releases in `finally`.
- [ ] Run ingestion embedding/batch commits and embedding-model switches through that lane, passing the captured ID to every `EmbeddingData`/vector write.
- [ ] Capture one query embedder ID and use it for query embedding plus every semantic/FTS/fallback search, including expanded variants; reject a changed identity.
- [ ] Change semantic, FTS, and LIKE queries to inner-join complete documents and require matching active document/vector embedder IDs.
- [ ] Add regression tests for switch races and orphan/stale/incomplete retrieval exclusion.

### Task 3: Durable byte sources and atomic reindex cleanup

**Files:** `lib/models/document.dart`, `lib/services/vector_store.dart`, `lib/services/document_management_service.dart`; model/vector/document-management tests.

- [ ] Add schema migration and persistence for optional `source_bytes` and use it for bytes-only/web documents.
- [ ] Reindex from durable bytes when no file path exists; retain bytes through replacement.
- [ ] Make staged-vector cleanup and rollback errors propagate, while retaining the old document until replacement commits.
- [ ] Add tests for byte-backed reindex and cleanup failure propagation.

### Task 4: Model lifecycle, settings async safety, and destructive controls

**Files:** `lib/services/model_management_service.dart`, `lib/services/chat_repository.dart`, `lib/ui/views/settings/settings_viewmodel.dart`, `lib/ui/views/settings/settings_view.dart`, document-library VM/view, localization ARBs; UI/service tests.

- [ ] Verify activation rollback and rollback failure reporting, and make errored partial-model deletion policy match the UI.
- [ ] Restore `clearChatHistory` as `Future<bool>` without removing confirmation or service API use.
- [ ] Guard every settings action after awaits, including clipboard failures, against disposed view models.
- [ ] Add confirmed crash-log clearing and sanitize startup-visible errors.
- [ ] Keep reindex badges/actions honest and fix the nullable test seam in `canReindex`.

### Task 5: Centralized redaction, backup posture, and generated artifacts

**Files:** `lib/services/logging_service.dart`, startup/UI error surfaces, native backup/storage files, `web/index.html`, localization/tests.

- [ ] Centralize redaction for `hf_` tokens, bearer credentials, Android paths, UNC paths, and Unix paths; apply it to persisted and displayed diagnostics.
- [ ] Preserve backup/privacy wording and native exclusion channels for database/model locations.
- [ ] Regenerate/restore plugin registrants through Flutter tooling and do not claim unsupported platform compilation.

### Task 6: Verification and report

**Files:** `.superpowers/sdd/2026-09-04-production-audit-remediation/task-4-report.md`.

- [ ] Run focused tests, full `flutter test --coverage`, `flutter analyze`, `flutter build web --release`, and `git diff --check`.
- [ ] Confirm corrected valid items: backup/privacy wording, switch-count confirmation, null identity handling, startup ordering, size handling, and Spanish UTF-8.
- [ ] Record exact commands/results, changed files, self-review, and any unresolved concerns honestly.
- [ ] Commit only the corrected scoped code/report (and this implementation plan if retained) with a Conventional Commit message.
