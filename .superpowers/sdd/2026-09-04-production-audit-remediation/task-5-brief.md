# Task 5: Bootstrap resilience, platform identity, metadata, and CI/release gates

Resolve audit findings H-4, M-3, M-10, L-8, L-9, L-10, L-11, L-12, and L-13.

Files:
- Modify `lib/bootstrap.dart`, `lib/services/environment_service.dart`, `macos/Runner/Configs/AppInfo.xcconfig`, macOS project configurations, `ios/Runner/Info.plist`, `android/gradle.properties`, `web/manifest.json`, `web/index.html`, `.github/workflows/main.yaml`, `.github/workflows/release.yaml`, `.github/cspell.json`, and relevant platform identity files.
- Update bootstrap tests and add deterministic config/build inspection scripts only where needed.

Requirements:

1. Install Flutter and platform error handlers before plugin/SQLite/locator setup. Wrap initialization in a catch boundary, record the error, and run a minimal localized retry/diagnostics error screen instead of leaving a blank app. A retry must be able to reattempt initialization.

2. Make flavor behavior meaningful for logging/configuration or remove unused flavor state while preserving the three existing flavor entrypoints. Production must not silently behave like development.

3. Set the macOS production bundle identifier to `wtf.rag.offline.sync.offline-sync`, replace the template copyright/name, and add a release-workflow check that fails if built metadata contains `com.example`. Align platform ids before public publication. Remove the unused iOS local-network usage prompt. Lower the Gradle heap default to fit smaller CI runners.

4. Replace boilerplate PWA title/description/theme metadata with the app’s real identity. Add the technical cspell terms required by the audit. Pin Linux packaging downloads and verify their SHA-256; pin/maintain GitHub Actions references according to repository policy.

5. Add `flutter build web --release` and `flutter build apk --debug --flavor development` smoke coverage to main CI. Schedule release verification or an equivalent automated check. Keep existing coverage and analyzer gates.

6. Use YAML/XML/plist/build inspection for configuration verification; do not add vacuous unit tests. Preserve release signing and target behavior.

Global constraints:
- `flutter analyze` must have 0 issues and the full suite must remain green.
- No secrets may be committed; missing release secrets fail loudly.
- Build/release downloads must be pinned and integrity-checked.

Implementation notes: Current bootstrap installs error handlers after several initialization steps. Current macOS AppInfo.xcconfig contains `com.example.myApp` and template copyright. Current release workflow already passes build-name/number from prior work; preserve those flags. Use exact current action SHA values from repository tooling/remote refs when pinning.

Report contract: write the detailed report to `.superpowers/sdd/2026-09-04-production-audit-remediation/task-5-report.md`, including exact config/build/test commands and output, files, self-review, and concerns. Commit with a Conventional Commit message and return only the short status contract.
