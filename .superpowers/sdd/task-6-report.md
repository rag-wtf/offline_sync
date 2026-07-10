# Task 6 Report: Align Flutter toolchain versions (M-23)

## Scope

- Updated `.github/workflows/release.yaml` to align release builds with PR CI on Flutter `3.35.x`.
- Left all other repository files unchanged.

## Change Made

- Changed `env.FLUTTER_VERSION` in `.github/workflows/release.yaml` from `3.38.x` to `3.35.x`.

## Verification

### Version alignment grep

Command:

```bash
rtk proxy grep -h "3.3" .github/workflows/main.yaml .github/workflows/release.yaml
```

Observed output:

```text
      flutter_version: "3.35.x"
  FLUTTER_VERSION: "3.35.x"
```

Result:

- Both workflow files report `3.35.x`.

### YAML parse

Command:

```bash
rtk proxy bash -lc 'if command -v ruby >/dev/null 2>&1; then ruby -e '\''require "yaml"; YAML.load_file(".github/workflows/release.yaml"); puts "YAML_OK"'\''; elif command -v python3 >/dev/null 2>&1; then python3 -c '\''import sys
try:
 import yaml
except Exception:
 sys.exit(2)
yaml.safe_load(open(".github/workflows/release.yaml"))
print("YAML_OK")'\''; else exit 3; fi'
```

Observed output:

```text
YAML_OK
```

This confirms the edited workflow parses as valid YAML in the current environment.

## Commit

- Conventional Commit subject: `ci: align release Flutter version with PR CI (3.35.x)`

## Concerns

- None at time of writing.
