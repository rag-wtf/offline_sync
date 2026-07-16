# Task 4 Report: Increment version/build number on every build (H-12)

## Scope

- Modified: `.github/workflows/release.yaml`
- Preserved existing Task 2-3 workflow changes.
- No unrelated files were edited before the required workflow commit.

## Implemented

1. Updated the `workflow_dispatch.inputs.version` description/default contract to require numeric semver with no leading `v`.
2. Added top-level derived env vars:
   - `BUILD_NUMBER: ${{ github.run_number }}`
   - `BUILD_NAME: ${{ github.event.inputs.version != '' && github.event.inputs.version || '1.0.0' }}`
3. Appended `--build-number=${{ env.BUILD_NUMBER }} --build-name=${{ env.BUILD_NAME }}` to all 7 `flutter build` invocations:
   - Android APK
   - Android App Bundle
   - iOS
   - Linux
   - macOS
   - Windows
   - Web

## Verification

### Required workflow checks

- `grep -c "build-number" .github/workflows/release.yaml`
  - Result: `7`
- Structural presence check via `rg` confirmed:
  - numeric version description at `.github/workflows/release.yaml:40`
  - `BUILD_NUMBER` at `.github/workflows/release.yaml:49`
  - `BUILD_NAME` at `.github/workflows/release.yaml:50`
  - all 7 build commands include both `--build-number` and `--build-name`
- YAML parse check:
  - `ruby` parser path unavailable in this environment
  - `python3` with PyYAML successfully parsed `.github/workflows/release.yaml`
  - Result: `yaml_ok`

### Analyzer / tests

- `flutter analyze`
  - Result: 0 errors, 0 warnings, 2 existing infos
  - Infos:
    - `lib/services/document_management_service.dart:126:14` `deprecated_member_use`
    - `lib/services/document_management_service.dart:134:24` `deprecated_member_use`
  - These infos are pre-existing and outside this task's ownership; this task did not increase analyzer infos.
- `flutter test`
  - Result: `All tests passed!`

## Commit

- `748e735` `ci: inject build-number/build-name into all release builds`

## Notes / Concerns

- `flutter analyze` exited non-zero because of 2 pre-existing info-level diagnostics outside the allowed edit scope. No errors or warnings were introduced by this task.
