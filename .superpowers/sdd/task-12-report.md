# Task 12 Report

## Task
Logging + crash-reporting + lifecycle batch (L-1, L-2, L-3, L-4) + L-27 runtime request

## Implementation
- Added level-aware logging in `lib/services/logging_service.dart` with `Level.warning` in release and `Level.debug` otherwise.
- Added persisted crash recording in `LoggingService.recordCrash(...)` using `SharedPreferences`, keeping the most recent 50 crash entries.
- Gated `String.fromEnvironment('HUGGINGFACE_TOKEN')` behind `kDebugMode` in `lib/services/auth_token_service.dart` so release builds do not auto-persist dart-define tokens.
- Wrapped app startup in `runZonedGuarded` in `lib/bootstrap.dart` and routed both zone errors and `FlutterError.onError` into the same crash log sink.
- Added Android 13+ notification permission handling in `lib/bootstrap.dart` using `background_downloader`'s built-in permissions API, with an inline comment documenting that progress notifications are best-effort if permission is denied.
- Added an app-root `AppLifecycleRoot` wrapper in `lib/app/main_app.dart` using `AppLifecycleListener` to close `locator<VectorStore>()` on `AppLifecycleState.detached`.
- Replaced the scoped raw `DEBUG:` startup/model-management traces with `LoggingService.debug(...)` in:
  - `lib/ui/views/startup/startup_viewmodel.dart`
  - `lib/services/model_management_service.dart`

## Tests Added
- `test/app/main_app_test.dart`
  - Verifies `VectorStore.close()` is called on detached lifecycle.
- `test/services/logging_service_test.dart`
  - Verifies non-release builds default to debug logging level.

## Verification
Commands run:

```bash
rtk flutter analyze
rtk flutter test
```

Results:
- `rtk flutter analyze`: passed, no issues found.
- `rtk flutter test`: passed, all tests passed.

Focused red/green checks also run during implementation:

```bash
rtk flutter test test/services/logging_service_test.dart
rtk flutter test test/app/main_app_test.dart
```

These were first observed failing before implementation, then passing after the changes.

## Files Changed
- `lib/services/logging_service.dart`
- `lib/services/auth_token_service.dart`
- `lib/bootstrap.dart`
- `lib/app/main_app.dart`
- `lib/ui/views/startup/startup_viewmodel.dart`
- `lib/services/model_management_service.dart`
- `test/app/main_app_test.dart`
- `test/services/logging_service_test.dart`

## Self-Review
- Confirmed the token fallback is debug-only and does not change stored-token behavior.
- Confirmed release logging will suppress debug/info noise through the logger level gate.
- Confirmed both framework and zone-level uncaught errors go to the same persisted sink.
- Confirmed lifecycle detach closes `VectorStore` from the app root without touching unrelated app structure.
- Confirmed Android notification permission uses an existing dependency API instead of introducing a new permission package.
- Confirmed edits stayed within the task scope, aside from adding focused tests and this report.

## Concerns
- Crash persistence is stored in `SharedPreferences` rather than a rotating file. It is persisted locally and satisfies the task's no-remote-reporter requirement, but it is intentionally lightweight.
