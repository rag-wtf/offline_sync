# Task 3 Report: Sign or explicitly mark the iOS artifact (H-17)

## Scope

- Modified `.github/workflows/release.yaml` only, within the `build-ios` job.
- Did not implement Option A.
- Did not edit unrelated files.

## Decision

- Applied Option B, per task resolution.
- Reason: no Apple distribution certificate or provisioning profile secrets were provided, so the workflow now marks the IPA as inspection-only instead of presenting it as distributable.

## Changes made

### `.github/workflows/release.yaml`

- Renamed the packaging step to `Create unsigned IPA (INSPECTION ONLY — not installable)`.
- Added a GitHub Actions warning banner that states the IPA is unsigned, not installable, and not suitable for submission.
- Renamed the generated IPA file to:
  - `offline_sync-${{ github.event.inputs.build_type }}-UNSIGNED.ipa`
- Renamed the uploaded artifact to:
  - `ios-${{ env.FLAVOR }}-${{ github.event.inputs.build_type }}-UNSIGNED-inspection-only${{ env.VERSION_SUFFIX }}`

## Verification

### YAML parsing

- Attempted the required parser command:

```bash
rtk python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yaml')); print('YAML OK')"
```

- Result: failed because `PyYAML` is not installed in this environment:

```text
ModuleNotFoundError: No module named 'yaml'
```

- Attempted a fallback local parser via Ruby stdlib YAML:

```bash
rtk ruby -e "require 'yaml'; YAML.load_file('.github/workflows/release.yaml'); puts 'YAML OK'"
```

- Result: `ruby` is not available in this environment.

### Structural inspection

Performed manual structural inspection of the edited workflow section:

- The `Create unsigned IPA (INSPECTION ONLY — not installable)` step remains a valid list item under `build-ios.steps`.
- The `run: |` block is correctly indented and contains four shell lines plus the warning echo.
- The `Upload iOS artifact` step remains a valid sibling step with unchanged `uses` and `path`.
- The artifact `name:` value remains a single scalar string with the required `-UNSIGNED-inspection-only` suffix inserted before `${{ env.VERSION_SUFFIX }}`.
- The generated IPA filename now includes `-UNSIGNED` and still targets `build/ios/ipa/*.ipa` for upload.

## Commit

- Created commit:
  - `ci(ios): mark unsigned IPA as inspection-only`

## Self-review

- The change resolves the audit issue addressed by Option B by making the unsigned artifact unmistakably non-distributable in both the filename and uploaded artifact name.
- The workflow still intentionally builds iOS with `--no-codesign`, matching the chosen Option B path and avoiding any unsupported signing setup.
- No Apple signing secrets were added or referenced, as required.

## Concerns

- No machine YAML parser was available locally, so validation is limited to structural inspection rather than parser-backed confirmation.
