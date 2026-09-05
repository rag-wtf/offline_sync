# Task 4 production audit remediation report

Date: 2026-09-05  
Base: `7e174e1`  
Fix-round commit: recorded after verification

## Findings addressed

- H-3: local-only privacy posture is explicit in Android backup policy, iOS/macOS storage-exclusion channels, native storage paths, and web metadata. The wording covers the local corpus, chat history, settings, diagnostics, and downloaded models; it does not claim protection from every possible OS or user-created copy.
- M-4: documents persist the embedding identity used to build their vectors. Retrieval filters semantic and keyword candidates by the active embedding identity and complete-document state; unknown or mismatched identities require re-indexing. Re-indexing stages vectors and swaps the document and source metadata transactionally after success.
- M-2: ingestion pins the active embedding model and contextual-retrieval setting, serializes model-sensitive embedding generation, and rejects an active-model change during a job. Retrieval reads its candidate snapshot transactionally.
- M-5: saved model IDs are restored only on exact identity matches and only after successful activation. Switch failures restore the prior native model where possible; deletion is exact-ID, best-effort, refreshes state, clears persisted/native active identity, and clears provider cache for active inference deletion.
- L-5: document-size limits are rounded consistently and exposed in Settings. All added user-visible strings are present in English and Spanish.
- L-16: crash diagnostics persist only safe messages and error types; credentials, bearer tokens, URLs, and local paths are redacted. Chat, model, token, and diagnostic controls catch expected failures and use confirmation dialogs where destructive.

## Verification evidence

- `flutter gen-l10n`: passed after correcting the Spanish placeholder metadata.
- `flutter analyze`: no errors; 8 style infos remain in the touched vector/UI/test code (line length, multiline-string, nullable cast, and raw-string guidance), so this report does not claim zero diagnostics.
- `flutter test test/services/vector_store_test.dart --reporter compact`: passed, 28 tests.
- Earlier combined focused run compiled successfully but exposed stale assumptions in inherited tests; vector setup and the unknown-saved-ID expectation were corrected, then the vector suite passed. The complete focused set was not rerun in this final quick pass.
- `flutter test --coverage`: not rerun in this final quick pass.
- `flutter build web --release`: not rerun in this final quick pass.
- `git diff --check`: passed after removing the trailing web blank line.
- Generated plugin registrants are present at `ios/Runner/GeneratedPluginRegistrant.h`, `ios/Runner/GeneratedPluginRegistrant.m`, and `macos/Flutter/GeneratedPluginRegistrant.swift`; they remain generated/ignored artifacts and are not hand-edited.

## Changed areas

Production changes cover settings recovery/data controls, model lifecycle, ingestion and re-indexing, vector schema/retrieval, logging redaction, backup exclusion, storage paths, privacy metadata, and localized English/Spanish UI copy. Tests cover document identity, retrieval isolation, transactional re-index failure safety, logging redaction, model persistence behavior, and Settings controls.

## Remaining concern

The required full test, coverage, and web-release commands were intentionally not rerun during this final quick-verification pass. The commit should therefore be treated as verified by analysis, localization generation, and the passing vector-store regression suite, with those broader commands still due in CI or a subsequent full verification run.
