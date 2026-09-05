# Task 4 report

## Scope

Implemented Task 4 from `task-4-brief.md` against base `dc69595`:

- H-3: opted into a no-backup posture for the SQLite database and model
  storage. Android disables backup and device transfer; iOS/macOS mark both
  Application Support and Application Documents excluded through the storage
  channel. Privacy copy now states that local corpus, history, settings,
  diagnostics, and models remain local.
- M-2: Settings now observes model status errors, displays model failure state,
  supports retry, and provides secure token entry/clear actions. Settings writes
  persisted values before publishing them, validates persisted model IDs and
  setting bounds, and reports save failures without claiming success.
- M-4: embedding-model changes warn about documents needing re-indexing;
  documents persist their embedding model identity, show mismatch state, and
  can be re-indexed through the existing ingestion pipeline.
- M-5: added confirmation-backed model deletion, chat-history clearing, and
  crash-log viewing/copying/clearing. Model deletion targets the exact selected
  model, clears active/cache state, removes verification metadata, and refreshes
  observable state.
- L-5: document size errors use stable rounded values and Settings exposes the
  configured limit.
- L-16: document rename/delete/re-ingest bookkeeping is transactional and
  consistent; partial vectors and in-flight hashes are cleaned up on failure.
  Crash/log diagnostics redact credentials, URLs, local paths, and error
  payloads before logging or persistence. Crash export copies only the already
  redacted diagnostics to the clipboard; no corpus import/export or overwrite
  path was added.

## Files changed

Production code and platform configuration:

`android/app/src/main/AndroidManifest.xml`,
`android/app/src/main/res/xml/backup_rules.xml`,
`android/app/src/main/res/xml/data_extraction_rules.xml`,
`ios/Runner/AppDelegate.swift`, `macos/Runner/MainFlutterWindow.swift`,
`web/index.html`, `lib/models/document.dart`,
`lib/services/device_capability_service.dart`,
`lib/services/document_management_service.dart`,
`lib/services/logging_service.dart`,
`lib/services/model_management_service.dart`,
`lib/services/model_recommendation_service.dart`,
`lib/services/rag_settings_service.dart`, `lib/services/vector_store.dart`,
`lib/services/vector_store_path_native.dart`,
`lib/ui/views/document_library/document_library_view.dart`,
`lib/ui/views/document_library/document_library_viewmodel.dart`,
`lib/ui/views/settings/settings_view.dart`,
`lib/ui/views/settings/settings_viewmodel.dart`,
`lib/ui/views/startup/startup_viewmodel.dart`,
`lib/l10n/arb/app_en.arb`, and `lib/l10n/arb/app_es.arb`.

Regression tests:

`test/helpers/test_helpers.dart`, `test/models/document_test.dart`,
`test/services/logging_service_test.dart`,
`test/services/model_management_service_test.dart`,
`test/services/rag_settings_service_test.dart`,
`test/services/vector_store_test.dart`,
`test/ui/views/settings/settings_viewmodel_test.dart`, plus the existing
document-library/settings widget suites exercised below.

## Verification

Commands and observed results:

```text
flutter test --reporter compact test/services/logging_service_test.dart test/services/model_management_service_test.dart test/services/rag_settings_service_test.dart test/services/vector_store_test.dart test/services/document_management_service_test.dart test/ui/views/settings/settings_viewmodel_test.dart test/ui/views/settings/settings_view_test.dart test/ui/views/document_library/document_library_viewmodel_test.dart test/ui/views/document_library/document_library_view_test.dart
00:12 +137: All tests passed!

flutter test test/ui/views/startup/startup_view_test.dart --plain-name "does not offer a repo link for a non-gated auth error"
00:00 +1: All tests passed!

flutter test --reporter compact
00:33 +452: All tests passed!

flutter analyze
No issues found! (ran in 9.3s)

flutter build web --release --target lib/main_production.dart
Compiling lib/main_production.dart for the Web... 153.9s
✓ Built build\web

git diff --check
no output; exit code 0
```

`flutter gen-l10n` completed successfully after updating both ARB files.
Generated Flutter registrants were restored before final status/staging:
Linux, macOS, and Windows generated registrant files are unchanged from the
base commit.

## Self-review

- Existing constructor/API shapes were preserved; injected deleter and service
  seams are optional.
- Expected model/settings, ingestion, cleanup, and diagnostics failures are
  represented as state or user-facing dialogs rather than unhandled errors.
- No telemetry or new network behavior was introduced.
- Diagnostics are redacted at the logging boundary and again when read from
  legacy persisted records.
- The web build emitted existing dependency Wasm dry-run compatibility warnings
  (`dart:ffi` and `flutter_gemma_mediapipe`); the release build still completed.

## Concerns / follow-up

- iOS/macOS native compilation was not available on the Windows host; the
  channel implementations were kept minimal and matched the Flutter channel
  contract. Android packaging was not run because the requested build smoke
  check was the documented production web target.
- The repository has no corpus export/import feature. Task 4's diagnostics
  export is clipboard-only and redacted, so there is no sensitive corpus
  overwrite/import behavior to exercise.
