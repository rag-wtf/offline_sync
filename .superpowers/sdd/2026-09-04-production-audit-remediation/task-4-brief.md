# Task 4: Settings recovery, data controls, embedder UX, and backup posture

Resolve audit findings H-3, M-2, M-4, M-5, L-5, and L-16.

Files:
- Modify `lib/ui/views/settings/settings_view.dart`, `settings_viewmodel.dart`, `lib/services/model_management_service.dart`, `chat_repository.dart`, `logging_service.dart`, document-library view/model files, and both localization ARB files.
- Modify `android/app/src/main/AndroidManifest.xml`, iOS/macOS native app delegates or a storage channel, `lib/services/vector_store_path_native.dart`, and the privacy copy in `web/index.html`.
- Update Settings/model-management/data-control/localization/widget tests.

Requirements:

1. Settings subscribes to model status with an `onError` handler and renders expected failures from `ModelInfo.errorMessage`/failure kind. Add token entry and clear-token actions to Settings. Retry must invoke the existing model service without an unhandled stream error.

2. Add confirmation-backed delete-model, clear-chat-history, and crash-log viewer/export/clear controls. Model deletion must remove the model through the model manager, be best-effort for multi-gigabyte files, refresh state, and not delete another model. Chat history and crash logs must use their existing service APIs.

3. Warn before embedding-model switches with the count of documents requiring re-indexing; expose mismatch badges and a per-document re-index action using the existing ingestion pipeline. Do not claim a document is searchable in the active embedding space when it is not.

4. Adopt the no-backup posture: exclude the SQLite database and model storage from iCloud/Finder and Android backup. Add Android backup policy and the smallest native storage-exclusion channel needed by iOS/macOS. Update privacy copy to state that local corpus/history/models are not included in OS cloud backups.

5. Format document-size errors with a stable rounded value and expose the configured size limit in Settings. Add/translate every new or changed string in `app_en.arb` and `app_es.arb`.

6. Keep constructor/API compatibility except optional seams, use real widget/service behavior tests, and avoid unhandled expected errors.

Global constraints:
- No telemetry or new network behavior.
- User-visible strings must be localized in both ARB files.
- `flutter analyze` must have 0 issues and the full suite must remain green.

Implementation notes: Existing model status streams emit errors for expected download failures; state is the source of truth for UI. The database is in Application Support and the plugin stores models in Application Documents on mobile. Native backup exclusion must cover both locations. Existing ARB keys include crash-log labels but may need additional keys for new controls.

Report contract: write the detailed report to `.superpowers/sdd/2026-09-04-production-audit-remediation/task-4-report.md`, including exact test commands/output, files, self-review, and concerns. Commit with a Conventional Commit message and return only the short status contract.
