# Task 4 production audit remediation report

Date: 2026-09-05
Base: `978e07d90d3658f3383f11da98dbb75b91655086`
Fix-round commit: recorded after final verification

## Findings addressed

- Embedding activation and ingestion now share a serialized coordinator and a pinned model identity. RAG pins query embedding and vector search to the same identity.
- Semantic, fallback, and FTS retrieval require complete documents and matching active embedder rows. Initialization removes orphan vectors and rebuilds the FTS index.
- Documents persist source bytes, allowing re-indexing of pathless and web-origin documents.
- Re-indexing stages vectors and atomically replaces the document; staged-vector cleanup failures propagate.
- Activation rollback is checked and rollback failure is propagated.
- Errored partial downloads follow the same deletion policy as the UI and are protected while actively downloading.
- `SettingsViewModel.clearChatHistory` is restored as `Future<bool>`. Async Settings actions guard post-await state and notifications, including clipboard failures.
- Crash-log deletion requires confirmation. Central redaction covers Hugging Face tokens, Bearer credentials, URLs, Android app paths, UNC paths, and Unix paths; startup errors are sanitized before display.
- English and Spanish strings were regenerated, and the report has no trailing whitespace.

## Final verification

- `flutter gen-l10n`: passed.
- `dart run build_runner build --delete-conflicting-outputs`: passed; 3 outputs generated. Generated registrants plus `app.logger.dart` and `app.router.dart` were restored to baseline; the required `app.locator.dart` coordinator registration remains.
- Focused regression suites, including document management, vector store, RAG/query expansion, model management, logging, Settings, startup, and document-library tests: passed.
- `flutter test --coverage --reporter compact`: passed, 474 tests; coverage output generated.
- `flutter analyze`: exit 1 with 31 non-error style diagnostics (infos/warnings only); no analyzer errors.
- `flutter build web --release`: the repository has no `lib/main.dart`, so the default command fails at entrypoint resolution. `flutter build web --release --target lib/main_production.dart`: passed and produced `build/web`; the tool emitted dependency Wasm dry-run and icon-font warnings.
- `git diff --check`: passed.
- Temporary test artifacts were absent, and generated platform registrants were restored.

## Changed areas

Production changes cover model lifecycle and identity pinning, ingestion/re-indexing, durable document sources, vector schema and retrieval isolation, logging redaction, Settings safety, destructive-action confirmation, startup error handling, and localized UI copy. Regression tests cover the corresponding concurrency, persistence, cleanup, platform, redaction, and lifecycle cases.
