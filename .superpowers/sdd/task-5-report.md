Status: DONE

Task: Phase 1 Task 5 - Add an analyze+test gate before release builds (H-14)

Files changed:
- .github/workflows/release.yaml

Summary:
- Added a new `verify` job as the first job under `jobs:`.
- The `verify` job runs `actions/checkout@v4`, `subosito/flutter-action@v2`, `flutter pub get`, `flutter analyze`, and `flutter test`.
- Added `needs: verify` to `build-android`, `build-ios`, `build-linux`, `build-macos`, `build-windows`, and `build-web`.
- Preserved the existing workflow content from prior tasks.

Verification:
- `grep -c "needs: verify" .github/workflows/release.yaml` returned `6`.
- YAML parse check passed for `.github/workflows/release.yaml`.

Notes:
- Per task instructions, this change is CI-only and limited to the release workflow plus this report.
