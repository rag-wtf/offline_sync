# Task 6: Dead-path removal, complete localization, UI cleanup, and hermetic tests

Resolve audit findings L-1, L-2, L-15, and L-18.

Files:
- Modify/delete only dead methods and call sites identified in `rag_service.dart`, `model_management_service.dart`, `document_management_service.dart`, `logging_service.dart`, `chat_repository.dart`, `rag_settings_service.dart`, `contextual_retrieval_service.dart`, `model_recommendation_service.dart`, `environment_service.dart`, and the touched chat/startup/settings/document-library/token UI.
- Modify `test/services/document_management_service_test.dart`, `test/services/vector_store_test.dart`, and affected test helpers.
- Add a deterministic ARB-unused-key check under the repository’s existing validation scripts.

Requirements:

1. Delete or deliberately wire the listed dead paths, including the duplicate `askWithRAG` generation implementation, without changing the active production flow or leaving dangling references. Keep one production generation path.

2. Route remaining startup/settings/library/chat/dialog/recommendation strings through `AppLocalizations`, add Spanish translations, and make the ARB-unused-key check report/fail on unused English keys. Do not use hard-coded fallback copy for normal localized UI paths.

3. Remove duplicate layout widgets and build-time post-frame registration. Migrate suppressed `RadioListTile.groupValue/onChanged` use to the current Flutter API where the project’s SDK supports it, with no new analyzer suppressions.

4. Move document/vector test fixtures to `Directory.systemTemp.createTemp`, preserve cleanup in teardown, and prove no repository-root fixture is created. Tests must continue asserting actual behavior.

Global constraints:
- User-visible strings added or changed belong in both ARB files.
- `flutter analyze` must have 0 issues and the full suite must remain green.
- No unrelated refactors.

Implementation notes: This is a final hygiene task after earlier tasks may have added localized Settings/data controls. Reuse those keys and service APIs; do not duplicate controls or reintroduce removed dead APIs merely to satisfy old tests—update tests to the supported production path.

Report contract: write the detailed report to `.superpowers/sdd/2026-09-04-production-audit-remediation/task-6-report.md`, including exact test/check commands and output, files, self-review, and concerns. Commit with a Conventional Commit message and return only the short status contract.
