# Implementation Plan - Code Review Fixes (Final)

Refactoring the `offline_sync` application to address critical architectural and compatibility issues identified in `docs/code_review_3.md`.

## User Review Required

> [!IMPORTANT]
> **Vector Storage Schema Update**: We have updated the internal `VectorStore` implementation (using `sqlite3`) to store embeddings as **JSON Strings** (TEXT) instead of BLOBs. This ensures future compatibility with PowerSync as requested. 

> [!NOTE]
> **Web Assets**: `web/wasm/litert*` files have been KEPT as per user request.

## Proposed Changes

### Architecture
#### [DELETE] [app.dart](file:///media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/app/view/app.dart)
- Remove the legacy VGV `App` widget.
- Move `AppLocalizations` configuration to `MainApp`.

#### [MODIFY] [main_app.dart](file:///media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/app/main_app.dart)
- configure `localizationsDelegates` and `supportedLocales` directly in `MaterialApp`.

### Data Layer (Vector Store)
#### [MODIFY] [vector_store.dart](file:///media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/services/vector_store.dart)
- Update `_onCreate` to define `embedding` column as `TEXT`.
- Update `insertEmbedding` and `insertEmbeddingsBatch` to `jsonEncode` the embedding list.
- Update `_semanticSearchAsync` and `_calculateSimilarities` to `jsonDecode` the embedding string back to `List<double>`.

### Operational Excellence
#### [NEW] [environment_service.dart](file:///media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/services/environment_service.dart)
- Implement `EnvironmentService` to track app flavors (`development`, `production`, `staging`).

#### [MODIFY] [bootstrap.dart](file:///media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/bootstrap.dart)
- Update code to initialize the `EnvironmentService` with the correct flavor during startup.

### Testing
#### [NEW] [startup_view_test.dart](file:///media/limcheekin/My Passport/ws/rag.wtf/offline_sync/test/ui/views/startup/startup_view_test.dart)
- Add widget test for `StartupView` to verify app launch.

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure all 5 tests pass.

### Manual Verification
- **App Launch**: Verify app launches on Linux and Web.
- **RAG Functionality**:
    1.  Ingest a document.
    2.  Ask a question.
    3.  Verify that relevant chunks are retrieved and the answer is generated.
- **Persistence**: Restart the app and verify vectors are still available (SQLite3 persistence).
