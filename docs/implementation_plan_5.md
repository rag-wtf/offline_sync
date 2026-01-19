# Implementation Plan: Code Review Improvements

This plan outlines the steps to address the remaining issues identified in `docs/code_review_5.md` and further improve the `offline_sync` codebase.

## Goal Description
Enhance the specific quality attributes of the application:
1.  **Reliability**: By implementing real device capability detection.
2.  **Maintainability**: By increasing test coverage, documenting APIs, and standardizing logging.
3.  **Scalability**: By refactoring large classes.
4.  **User Experience**: By supporting localization.

## User Review Required
> [!NOTE]
> **Platform Detection Strategy**: We plan to use `system_info_plus` to replace hardcoded RAM/Storage values. This requires validating the package's reliability across different Android versions.

## Proposed Changes

### 1. Dynamic Platform Capability Detection (Major Issue #9)
Currently, `DeviceCapabilityService` returns hardcoded values for RAM and storage on most platforms.

#### [MODIFY] [device_capability_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/device_capability_service.dart)
- Import `system_info_plus`.
- Implement `_getAndroidCapabilities` (and potentially others) to fetch real RAM size.
- Fallback to safe defaults only if detection fails.

### 2. Comprehensive Test Coverage (Medium Issue #23)
Several core services lack unit tests.

#### [NEW] [rag_service_test.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/test/services/rag_service_test.dart)
- Test `askWithRAG` flow (mocking dependencies).
- Test token budget logic (`buildHistoryWithBudget`).
- Test `splitIntoChunks` logic.

#### [NEW] [query_expansion_service_test.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/test/services/query_expansion_service_test.dart)
- Verify `expandQuery` returns variants.
- Verify fallback behavior on error.

#### [NEW] [reranking_service_test.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/test/services/reranking_service_test.dart)
- Verify `rerank` sorts results correctly.

### 3. Consistent Logging Strategy (Medium Issue #13)
Replace mixed `debugPrint`/`log` usage with the `logger` package for structured logging.

#### [MODIFY] [app.locator.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/app/app.locator.dart)
- Register `Logger`.

#### [MODIFY] [All Services]
- Inject `Logger`.
- Replace `log()` and `debugPrint()` with `_logger.d()`, `_logger.i()`, `_logger.e()`.

### 4. API Documentation (Medium Issue #14)
Add DartDoc comments to all public methods in:
- `RagService`
- `VectorStore`
- `ChatViewModel`

### 5. Code Refactoring (Medium Issue #15)
Break down large classes.

#### [NEW] [chat_ui_helpers.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/chat/chat_ui_helpers.dart)
- Extract `_MessageTile` and `ChatInput` widgets from `chat_view.dart`.

#### [NEW] [rag_token_manager.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/rag_token_manager.dart)
- Extract token estimation and budget calculation logic from `RagService`.

### 6. Localization (Minor Issue #24)
- Create ARB files for supported languages.
- Replace hardcoded strings in UI with `AppLocalizations.of(context)`.

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure new tests pass and no regression.
- Check code coverage report to ensure > 80% coverage on new areas.

### Manual Verification
- **Platform Detection**: Run on an Android device/emulator and verify logs show actual RAM usage.
- **Logging**: Verify logs appear in console with correct formatting.
- **Localization**: Change device language and verify UI updates.
