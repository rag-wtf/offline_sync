# Task 5 implementation report

Date: 2026-09-05
Worktree: `production-audit-fixes`
Scope: H-4, M-3, M-10, L-8, L-9, L-10, L-11, L-12, L-13

## Finding-by-finding evidence

| Finding | Remediation and evidence |
|---|---|
| H-4 | `macos/Runner/Configs/AppInfo.xcconfig` now defines the production product name, `wtf.rag.offline.sync.offline-sync` bundle identifier, and a current Offline Sync copyright. `release.yaml` verifies the built macOS `Info.plist` identifier and rejects template identities. |
| M-3 | `lib/bootstrap.dart` installs `FlutterError.onError` and `PlatformDispatcher.instance.onError` before downloader, model, SQLite, locator, or UI setup. Initialization is inside an `Object` catch, failures are persisted through a safe crash-recording wrapper, and a localized retry/diagnostics `MaterialApp` is rendered. `test/bootstrap_test.dart` proves handlers are installed before a simulated initialization failure and verifies the failure UI. |
| M-10 | `.github/workflows/main.yaml` now has production web release and development Android debug smoke jobs. `release.yaml` runs its verification job weekly in addition to manual dispatch. |
| L-8 | `web/index.html` and `web/manifest.json` use the Offline Sync product title, description, and matching application colors rather than Flutter/VGV boilerplate. |
| L-9 | Linux packaging downloads in `release.yaml` use dated release URLs and strict SHA-256 checks. All 37 GitHub Actions references in the two workflows are pinned to 40-character commit SHAs with version comments. |
| L-10 | Android now uses the product reverse-domain identity with the Android-required underscore form, while Apple and desktop configurations retain the hyphenated product identity. The release workflow checks built Android and macOS metadata for the expected identity and rejects `com.example`/template identities. |
| L-11 | Android Gradle defaults are reduced to `-Xmx4G`, 1G Metaspace, and 256m reserved code cache in `android/gradle.properties`. |
| L-12 | `NSLocalNetworkUsageDescription` was removed from `ios/Runner/Info.plist`; no iOS local-network prompt remains. |
| L-13 | Flavor state now configures `LoggingService`; bootstrap configures the flavor before initialization and every log message carries the flavor context. `test/services/environment_service_test.dart` verifies the configuration link. |

## Commands and results

- `flutter gen-l10n` — PASS.
- `flutter test test/bootstrap_test.dart test/services/environment_service_test.dart test/services/logging_service_test.dart` — PASS, 21 tests.
- `flutter test --coverage --reporter compact` — PASS, 490 tests. Coverage: 4523/4813 instrumented lines (93.97%). This remains below the repository’s existing 95% CI gate; no broad or vacuous exclusions were added. Meaningful coverage follow-up remains a Task 6 carryover recorded by the remediation ledger.
- `flutter analyze` — PASS, `No issues found!`.
- `npx --yes cspell --no-progress --config .github/cspell.json "**/*.md"` — PASS, 35 files and 0 issues.
- Python YAML parse of `.github/workflows/main.yaml` and `.github/workflows/release.yaml` — PASS; expected jobs parsed.
- JSON parsing of `.github/cspell.json` and `web/manifest.json` — PASS.
- XML/plist and platform identity validation — PASS; iOS local-network key absent, PWA metadata matches, and no template identity was found in platform inputs.
- Action reference validation — PASS, 37 workflow references and all are 40-character SHAs.
- `flutter build web --release --target lib/main_production.dart` — PASS, production web bundle built. Flutter emitted dependency Wasm dry-run warnings and an icon-font warning; these did not fail the build.
- `flutter build apk --debug --flavor development --target lib/main_development.dart` — PASS, `build/app/outputs/flutter-apk/app-development-debug.apk` produced. The local build used Java 25/Gradle 9 and completed successfully; hosted CI uses the workflow’s Java 17 setup.
- `git diff --check` — PASS.

Generated Flutter registrant churn from `gen-l10n`, web, and Android commands was restored for the seven known registrant files before commit.

## Environment limitations

- macOS and iOS native builds were not available on this Windows runner; their plist/configuration checks were performed statically.
- The full suite passes, but the existing 95% coverage gate remains red at 93.97% and is intentionally not weakened in this task.
- The requested `gpt-5.6-terra` reviewer could not be dispatched in the resumed session because no subagent connector was available; the implementation received local diff, static-config, test, analyze, and build verification.
