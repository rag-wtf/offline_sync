# Task 6 report — production audit remediation

**Date:** 2026-09-06
**Worktree:** `production-audit-fixes`
**Scope:** Audit findings L-1, L-2, L-15, L-18, and the carried cross-cutting coverage blocker.

## Implementation summary

### L-1 — dead paths and duplicate generation APIs

- `RagService.askWithRAG` is now a compatibility adapter over the active streamed generation path. It aggregates the stream result and metadata instead of maintaining a second prompt/model-generation implementation.
- Removed unused `refresh` from `ModelManagementService` and the unused document maintenance wrappers (`refreshDocument`, `deleteAllDocuments`, `hasDocumentChanged`, `optimizeDatabase`, and `cancelIngestion`) from `DocumentManagementService`; the dead `optimizeDatabase` vector-store wrapper was removed as well. The vector store's transactional `deleteAllDocuments` remains because it is covered active storage behavior.
- Reviewed the listed logging, chat repository, RAG settings, contextual retrieval, recommendation, environment, and chat-viewmodel paths. Their remaining code is active production behavior or an intentionally used persistence/configuration API; no duplicate call site was retained.
- Preserved the active `askWithRAGStream` flow, including its metadata and token accounting.
- Recommendation failure text is now supplied by localized callbacks from the startup view model rather than being embedded in the service.

### L-2 — localization and ARB drift

- Routed remaining user-visible startup, settings, document-library, chat, token-dialog, and recommendation strings through `AppLocalizations`.
- Added matching English and Spanish entries to `lib/l10n/arb/app_en.arb` and `lib/l10n/arb/app_es.arb`; ARB key parity is verified at 173 message keys.
- Regenerated localization output with `flutter gen-l10n`.
- Added `tool/check_arb_unused.dart`, a deterministic validation script that parses English ARB keys, scans non-generated `lib/**/*.dart` source for `AppLocalizations` getters, and fails on an unused English key. Both CI workflows run it after localization generation.
- Validation result: `ARB validation passed: 173 English keys are referenced.`

### L-15 — UI hygiene

- Removed the duplicate chat layout spacer.
- Removed build-time post-frame registration from `ChatView`; scroll-listener lifecycle is attached and detached explicitly, with post-frame scrolling scheduled by the view model in response to listener events.
- Migrated supported settings radio groups to `RadioGroup<String>` and removed the deprecated `RadioListTile` group-value/on-change usage and suppression.

### L-18 — test fixture isolation

- Moved document and vector-store fixtures into per-test directories created below `Directory.systemTemp`.
- Added teardown cleanup for temporary files/directories and database handles.
- Added an explicit assertion that the vector-store test database is outside the repository and that repository-root `vectors.db` is absent. No repository-root document fixture is created by the updated tests.

### Coverage blocker carried from Task 4

- Added meaningful coverage for vector replacement, document-library reindex UI and view-model failures, settings error handling, localized recommendation messages, and startup/token behavior.
- Full suite result: **495 tests passed, 0 failed**.
- Exact regenerated LCOV result: **LH 4,660 / LF 4,918 = 94.754% line coverage**.
- The enforced CI threshold remains 95%; it was not lowered, disabled, or bypassed. The current result is 13 covered lines short of the minimum 4,673 covered lines required by the integer gate. This report records the shortfall explicitly per the completion request; CI's coverage step will remain red until additional meaningful production coverage is added.

## Validation evidence

| Command | Result |
|---|---|
| `flutter gen-l10n` | Passed; generated localization output refreshed. |
| `dart run tool/check_arb_unused.dart` | Passed: 173 English keys referenced. |
| `flutter analyze` | Passed: `No issues found!` |
| Focused startup/token tests | Passed: 14 tests. |
| Focused settings/document-library/chat view tests | Passed: 17 tests. |
| Focused chat/startup view-model tests | Passed: 61 tests. |
| Focused recommendation/startup view-model tests | Passed: 61 tests. |
| New vector replacement test | Passed. |
| New settings error test | Passed. |
| New document-library reindex test | Passed. |
| New localized settings-error UI test | Passed. |
| `flutter test --coverage --reporter compact` | Passed: 495 tests, 0 failures. Coverage: **4,660/4,918 = 94.754%**. |
| JSON config and ARB parity check | Passed: `.github/cspell.json`, both ARB files parse; 173 keys match. |
| `git diff --check` | Passed. |
| `flutter build web --release --target lib/main_production.dart` | Passed: `build/web` produced. Wasm dry-run emitted expected plugin/`dart:ffi` incompatibility warnings; normal web build succeeded. |
| `flutter build apk --debug --flavor development --target lib/main_development.dart` | Passed: `app-development-debug.apk` produced. |
| CI-scope Markdown cspell check | Passed: 35 files checked, 0 issues. |

## Limitations and follow-up

- Coverage is 94.754%, below the enforced 95% gate. The implementation does not claim the gate passes and does not change the gate. Follow-up should add at least 13 meaningful covered lines before CI can pass.
- A broad ad-hoc cspell scan over Dart, YAML, ARB, tool, and Markdown files reports existing technical terms and the Spanish translation vocabulary under the configured English dictionary. The CI workflow's configured spell-check scope is Markdown, so translated ARB text is not added to the English dictionary merely to silence that diagnostic.
- Web normal release compilation and Android development debug compilation passed. The web Wasm dry-run and Android toolchain emitted non-fatal environment/toolchain warnings. Desktop and iOS builds were not run on this Windows host.
- No external subagent/reviewer connector was available in this resumed session; validation was performed locally with the repository's Flutter/Dart tooling.
