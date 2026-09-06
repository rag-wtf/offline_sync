# Task 2 implementation report

## Scope

Implemented audit findings C-2, H-2, M-8, and M-9 in the
`production-audit-fixes` worktree.

## Files changed

- `lib/services/model_management_service.dart`
  - Uses a conditional checksum backend so web builds never construct
    `dart:io File` instances for plugin-managed `blob:`, Cache API, or OPFS
    paths.
  - Keeps native unresolved paths fail-closed.
  - Persists native verification metadata in `SharedPreferences` containing
    model id, path, size, modification marker, and expected SHA-256 digest.
  - Removes the process-only checksum cache and trusts persisted metadata only
    when every metadata field still matches.
  - Runs the production SHA-256 stream in `compute()`.
  - Distinguishes verified, mismatch, and read-error outcomes. Only confirmed
    mismatches delete the file; read failures preserve it and expose a specific
    retryable error.
  - Catches `Object` at download and activation boundaries and clears the
    memoized initialization future after failure.
- `lib/services/model_checksum.dart`
- `lib/services/model_checksum_io.dart`
- `lib/services/model_checksum_types.dart`
- `lib/services/model_checksum_web.dart`
- `test/services/model_management_service_test.dart`
  - Added persisted cache hit/miss, read-failure preservation, Object-level
    download/activation failure, and initialization retry coverage.
- `test/services/model_management_service_web_test.dart`
  - Added a production-path web-shaped `blob:` resolver test.
- `test/ui/views/startup/startup_viewmodel_test.dart`
  - Added startup retry coverage after initialization failure.

## Verification

- TDD red check: the new cache tests initially failed to compile because the
  planned `sharedPreferencesLoader` seam did not yet exist.
- `flutter test test/services/model_management_service_test.dart test/ui/views/startup/startup_viewmodel_test.dart`
  - Result: `00:03 +86: All tests passed!`
- `flutter test test/services/model_management_service_test.dart test/ui/views/startup/startup_viewmodel_test.dart test/services/model_management_service_web_test.dart`
  - Result: `00:03 +86: All tests passed!` (the Chrome-only test is skipped on
    the native test platform).
- `flutter analyze`
  - Result: `No issues found!`
- `flutter build web --target lib/main_production.dart --no-pub`
  - Result: `✓ Built build\\web`.
- `flutter test`
  - Result: `00:17 +422: All tests passed!`

## Self-review

- Native model paths are converted to a checksum file only after the
  `kIsWeb` guard.
- Web plugin-managed paths are accepted as plugin-verified and do not enter
  the native checksum backend.
- Metadata is written only after immediate verification succeeds, and a stale
  path/size/mtime/digest record causes a fresh hash.
- Mismatch and read-error messages are separate, and the delete operation is
  reachable only from the mismatch branch.
- `StateError`, `UnsupportedError`, and `ArgumentError` are covered by the
  `Object` catches at the relevant boundaries; model state is updated to
  `error` instead of remaining `downloading`.
- Generated platform registrants were restored after Flutter tooling runs.

## Concerns

The Chrome test command was attempted with
`flutter test --platform chrome test/services/model_management_service_web_test.dart`.
It reached the test loading phase but stalled in this environment, so it was
terminated. The production web build completed successfully and compiled the
conditional web checksum backend; the Chrome runner itself remains an
environment limitation.

## Fix round 1

Commit: `74103c1 fix(models): close task 2 review gaps`

Addressed all review findings:

- Moved compatibility checks inside the activation and download `Object`
  boundaries. Capability `StateError`, `UnsupportedError`, and `ArgumentError`
  failures now mark the model as `error`, publish the operation error, and
  remove any active download entry.
- Replaced the default resolver's catch-and-null behavior with an internal
  resolved/unavailable/read-error result, preserving retryable resolver/I/O
  failures without deleting model files.
- Reworked the read-failure regression to use an existing file and an injected
  verifier failure; it asserts the file remains.
- Added a confirmed-mismatch test proving persisted checksum metadata is
  cleared after deletion.
- Converted the Chrome-only web test into a deterministic normal-suite test
  using the production web guard override. It exercises both `blob:` and
  `opfs:` paths and fails if either reaches the native verifier/File seam.
- Added `ArgumentError` and status-stream observation coverage for download,
  activation, and capability-resolution failures.

### Fix-round verification

- `flutter test test/services/model_management_service_test.dart --plain-name "clears persisted checksum metadata after a confirmed mismatch"`
  - Result: `00:00 +1: All tests passed!`
- `flutter test test/services/model_management_service_test.dart test/services/model_management_service_web_test.dart`
  - Result: `00:00 +63: All tests passed!`
- `flutter test test/services/model_management_service_test.dart test/services/model_management_service_web_test.dart test/ui/views/startup/startup_viewmodel_test.dart`
  - Result: `00:04 +91: All tests passed!`
- `flutter analyze`
  - Result: `No issues found! (ran in 3.2s)`
- Generated platform registrants were restored before commit.

No full suite was started for this fix round, per the task instruction.

### Fix-round self-review and concerns

The original native persisted-metadata path, `compute()` hashing, conditional
web imports, mismatch-only deletion, and failed-initialization retry remain
unchanged. The only new test seam is an optional web-platform override used by
the deterministic unit test; production defaults to `kIsWeb`. No browser
runner is required for the normal focused suite.
