# Phase 1 — Release Blockers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
> Master plan: [2026-07-07-production-readiness-remediation.md](2026-07-07-production-readiness-remediation.md). Read the **task shapes** and **Global Constraints** there first.

**Goal:** Make the Android and iOS release artifacts installable/publishable, gate every release build on analyze+test, resolve the web cross-origin-isolation risk, and align toolchains.

**Architecture:** Almost all of Phase 1 is CI/platform config (GitHub Actions, Gradle, manifests, plist, `index.html`). These are **Config/CI/platform** tasks — the "verify" step is a build/inspect command, never a `flutter test`. One CI job (analyze+test gate) is added and wired as a `needs:` prerequisite.

**Tech Stack:** GitHub Actions (`.github/workflows/`), Android Gradle Kotlin DSL, `apksigner`, Flutter build CLI.

## Global Constraints

See master plan. Phase-specific:
- CI secrets referenced (`ANDROID_KEYSTORE_*`, Apple signing) must be documented as **required repo secrets** in the workflow comments; if a secret is absent the job must **fail loudly**, never silently produce an unsigned artifact.
- Do not change `pubspec.yaml` `version:` format (`major.minor.patch+build`); the build number is injected at build time (H-12).

---

## Task 1: Add INTERNET permission to release Android manifest (C-1) + notifications (L-27)

**Shape:** Config/platform. Verification = manifest merge inspection.

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

**Why:** `INTERNET` is declared only in the debug/profile overlays (`android/app/src/debug/AndroidManifest.xml:6`), which are excluded from release. No dependency library manifest adds it (audit's exhaustive pub-cache check). The release APK/AAB therefore cannot download models — the mandatory first-run flow — and this is invisible in debug/profile testing. `POST_NOTIFICATIONS` (L-27) is folded in here: `bootstrap.dart:36-43` configures a foreground download notification, silently suppressed on Android 13+ without the permission.

> **Deferred (L-27 completion):** declaring `POST_NOTIFICATIONS` is necessary but **not sufficient** on Android 13+ — the notification also needs a **runtime permission request** (Dart code). That request is out of scope for this config-only task; it is completed in **Phase 4 Task 12** (or add a `permission_handler` request at startup). This task only lands the declaration.

- [ ] **Step 1: Add the permissions**

In `android/app/src/main/AndroidManifest.xml`, add these two lines immediately after the opening `<manifest …>` tag (before the existing `RUN_USER_INITIATED_JOBS` line at :3):

```xml
    <!-- Required for model downloads from HuggingFace (release builds) -->
    <uses-permission android:name="android.permission.INTERNET" />
    <!-- Android 13+: required to show download-progress foreground notification -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

- [ ] **Step 2: Verify the merged manifest contains INTERNET**

Run:
```bash
flutter build apk --release --flavor production --target lib/main_production.dart
```
Then inspect the built APK directly (robust — independent of AGP's intermediate paths):
```bash
aapt dump permissions build/app/outputs/flutter-apk/app-production-release.apk | grep INTERNET
```
Expected: `uses-permission: name='android.permission.INTERNET'`. (`aapt` ships in `$ANDROID_SDK_ROOT/build-tools/*/`.) Fallback if `aapt` is unavailable: `grep -r "android.permission.INTERNET" build/app/intermediates/merged_manifests/` — but that intermediate path shifts by AGP version, so prefer the `aapt` check.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "fix(android): declare INTERNET + POST_NOTIFICATIONS in release manifest"
```

---

## Task 2: Sign release Android artifacts in CI (C-2) + remove stale TODO (L-21)

**Shape:** Config/CI. Verification = `apksigner verify`.

**Files:**
- Modify: `.github/workflows/release.yaml` (build-android job, `:52-93`)
- Modify: `android/app/build.gradle.kts` (`:31` stale TODO)

**Why:** The `release` signing config reads `ANDROID_KEYSTORE_*` env vars, falling back to `key.properties` (which is gitignored/absent). CI sets neither, so AGP emits an **unsigned** artifact without failing. It is uninstallable and Play-rejected. Fix: inject keystore from GitHub Secrets and add a post-build signature verification that fails the job if unsigned.

**Interfaces:**
- Consumes (repo secrets, must be created by a maintainer): `ANDROID_KEYSTORE_BASE64` (base64 of the `.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD`.
- Produces: signed `*.apk`/`*.aab` verified by `apksigner`.

- [ ] **Step 1: Remove the stale template TODO (L-21)**

In `android/app/build.gradle.kts`, delete line 31:
```kotlin
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
```
(The `applicationId` at :32 is already set correctly to `wtf.rag.offline.sync.offline_sync`.)

- [ ] **Step 2: Decode the keystore in CI before the build**

In `.github/workflows/release.yaml`, in the `build-android` job, add a step **after** "Install dependencies" (`:73`) and **before** "Build Android APK" (`:75`):

```yaml
      - name: Decode Android keystore
        env:
          ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          if [ -z "$ANDROID_KEYSTORE_BASE64" ]; then
            echo "::error::ANDROID_KEYSTORE_BASE64 secret is not set. Refusing to build an unsigned release."
            exit 1
          fi
          echo "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$RUNNER_TEMP/release.jks"
          echo "ANDROID_KEYSTORE_PATH=$RUNNER_TEMP/release.jks" >> "$GITHUB_ENV"
```

- [ ] **Step 3: Pass signing env into the Gradle builds**

The APK/AAB build steps invoke `flutter build`, which delegates to Gradle; the `build.gradle.kts` signing config already reads `System.getenv("ANDROID_KEYSTORE_PATH"|"_ALIAS"|"_PASSWORD"|"_PRIVATE_KEY_PASSWORD")` (`:43-47`). Add the env block to **both** the "Build Android APK" (`:75-76`) and "Build Android App Bundle" (`:78-80`) steps:

```yaml
        env:
          ANDROID_KEYSTORE_PATH: ${{ env.ANDROID_KEYSTORE_PATH }}
          ANDROID_KEYSTORE_ALIAS: ${{ secrets.ANDROID_KEYSTORE_ALIAS }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD }}
```
(Place `env:` under each `run:` step. The `run:` line itself is unchanged.)

- [ ] **Step 4: Verify the signature after the APK build**

Add a step after "Build Android APK" (before the AAB build):

```yaml
      - name: Verify APK signature
        run: |
          APK=$(find build/app/outputs/flutter-apk -name "*-release.apk" | head -n 1)
          echo "Verifying $APK"
          "$ANDROID_SDK_ROOT/build-tools"/*/apksigner verify --verbose "$APK"
```
Expected: `Verified using v1 scheme … true` / `v2 … true` and exit 0. If the artifact is unsigned, `apksigner` exits non-zero and fails the job — which is the guardrail C-2 asks for.

- [ ] **Step 5: Document required secrets**

At the top of `build-android` (as a YAML comment above `runs-on:`), add:
```yaml
    # Requires repo secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
    # ANDROID_KEYSTORE_ALIAS, ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD.
```

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yaml android/app/build.gradle.kts
git commit -m "ci(android): sign release artifacts from secrets and verify signature"
```

---

## Task 3: Sign or explicitly mark the iOS artifact (H-17)

**Shape:** Config/CI. Verification = presence of signing OR explicit non-distributable marking.

**Files:**
- Modify: `.github/workflows/release.yaml` (build-ios job, `:95-129`)

**Why:** The job builds with `--no-codesign` then hand-zips `Payload/` into an `.ipa`. That artifact cannot be installed or submitted to TestFlight/App Store. Two acceptable resolutions — pick per whether Apple signing secrets exist:

**Decision point:** If the team has an Apple distribution certificate + provisioning profile available as secrets, do **Option A**. Otherwise do **Option B** (honest labeling) so the artifact is never mistaken for distributable. Ask the maintainer which; default to **B** if unknown (it is non-destructive and unblocks the audit finding without fabricating credentials).

- [ ] **Step 1 (Option B — default): Mark the artifact inspection-only and fail-safe the naming**

Replace the "Create unsigned IPA" step (`:118-123`) body's zip name and add a warning banner. Change the "Upload iOS artifact" name (`:128`) to include `-UNSIGNED-inspection-only`:

```yaml
      - name: Create unsigned IPA (INSPECTION ONLY — not installable)
        run: |
          echo "::warning::This IPA is unsigned and cannot be installed or submitted. For distribution, configure Apple signing secrets and use Option A."
          cd build/ios/iphoneos
          mkdir Payload
          cp -r Runner.app Payload/
          zip -r ../ipa/offline_sync-${{ github.event.inputs.build_type }}-UNSIGNED.ipa Payload
```
```yaml
      - name: Upload iOS artifact
        uses: actions/upload-artifact@v4
        with:
          name: ios-${{ env.FLAVOR }}-${{ github.event.inputs.build_type }}-UNSIGNED-inspection-only${{ env.VERSION_SUFFIX }}
          path: build/ios/ipa/*.ipa
```

- [ ] **Step 1 (Option A — if signing secrets exist): Sign with fastlane/xcode**

Replace `--no-codesign` (`:113`) with a signed archive+export flow using `Apple_Distribution` cert and a provisioning profile installed from secrets (`APPLE_CERT_BASE64`, `APPLE_CERT_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`). Use `flutter build ipa --export-options-plist ExportOptions.plist`. Document the required secrets as a YAML comment. (Full fastlane match setup is out of scope; if choosing A, spike it in a follow-up — but do not ship `--no-codesign` labeled as a normal release.)

- [ ] **Step 2: Verify the workflow parses**

Run:
```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yaml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yaml
git commit -m "ci(ios): mark unsigned IPA as inspection-only (or sign for distribution)"
```

---

## Task 4: Increment version/build number on every build (H-12)

**Shape:** Config/CI. Verification = build-number appears in build args.

**Files:**
- Modify: `.github/workflows/release.yaml` (all `flutter build` invocations)

**Why:** The workflow `version` input feeds only `VERSION_SUFFIX` (filenames). No build passes `--build-number`/`--build-name`, so `versionCode`/`CFBundleVersion` stay permanently `1` — Play Store rejects every upload after the first. Fix: derive build number from `github.run_number` and build name from the version input, and pass to every build.

- [ ] **Step 1: Add derived env vars (build-name MUST be numeric)**

First fix the `version` input so it cannot carry a leading `v` — `--build-name` sets iOS `CFBundleShortVersionString`, which App Store rejects unless it is a numeric dot-separated string (`v1.0.0` is rejected). In `.github/workflows/release.yaml`, change the input description/default (`:40-43`) to require numeric semver:
```yaml
      version:
        description: "Numeric version, e.g. 1.0.0 (NO leading 'v'). Used for build-name and artifact filenames."
        required: false
        type: string
        default: ""
```
Then in the top-level `env:` block (`:45-49`), add:
```yaml
  BUILD_NUMBER: ${{ github.run_number }}
  BUILD_NAME: ${{ github.event.inputs.version != '' && github.event.inputs.version || '1.0.0' }}
```
(Because the input is now guaranteed numeric, `BUILD_NAME` is a valid `CFBundleShortVersionString`/`versionName`. `VERSION_SUFFIX` at `:49` still prefixes filenames with `-`, unaffected.)

- [ ] **Step 2: Append build flags to every `flutter build`**

Add `--build-number=${{ env.BUILD_NUMBER }} --build-name=${{ env.BUILD_NAME }}` to each of these build steps:
- Build Android APK (`:76`)
- Build Android App Bundle (`:80`)
- Build iOS (`:113`)
- Build Linux (`:154`)
- Build macOS (`:265`)
- Build Windows (`:296`)
- Build Web (`:333`)

Example (APK, `:76`) becomes:
```yaml
        run: flutter build apk --${{ github.event.inputs.build_type }} --flavor ${{ env.FLAVOR }} --target ${{ env.TARGET }} --build-number=${{ env.BUILD_NUMBER }} --build-name=${{ env.BUILD_NAME }}
```
(Linux/Windows/Web builds have no flavor; keep their existing flags and only append the two new ones.)

- [ ] **Step 3: Verify**

```bash
grep -c "build-number" .github/workflows/release.yaml
```
Expected: `7` (one per build step).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yaml
git commit -m "ci: inject build-number/build-name into all release builds"
```

---

## Task 5: Add an analyze+test gate before release builds (H-14)

**Shape:** CI. Verification = `needs:` wiring present; job runs analyze+test.

**Files:**
- Modify: `.github/workflows/release.yaml`

**Why:** `release.yaml` builds and uploads artifacts with no `flutter analyze`/`flutter test`. Those run only in `main.yaml` on push/PR to `main`; a `workflow_dispatch` release bypasses them. Add a `verify` job and make every build job `needs: verify`.

- [ ] **Step 1: Add the verify job**

Insert as the first job under `jobs:` (before `build-android`, at `:51`):

```yaml
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: "stable"
          cache: true
      - name: Install dependencies
        run: flutter pub get
      - name: Analyze
        run: flutter analyze
      - name: Test
        run: flutter test
```

- [ ] **Step 2: Gate every build job on it**

Add `needs: verify` to each build job's definition (immediately under the job key, above its `if:`). For example `build-android` (`:52`) becomes:
```yaml
  build-android:
    needs: verify
    if: ${{ github.event.inputs.platform == 'all' || github.event.inputs.platform == 'android' }}
```
Repeat for `build-ios`, `build-linux`, `build-macos`, `build-windows`, `build-web`.

- [ ] **Step 3: Verify**

```bash
grep -c "needs: verify" .github/workflows/release.yaml
```
Expected: `6`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yaml
git commit -m "ci: gate all release builds on analyze+test verify job"
```

---

## Task 6: Align Flutter toolchain versions (M-23)

**Shape:** Config. Verification = versions match.

**Files:**
- Modify: `.github/workflows/release.yaml:46`
- Reference: `.github/workflows/main.yaml:22` (`3.35.x`), `pubspec.yaml:8` (`^3.35.0`)

**Why:** Release builds on `3.38.x` while PR CI (and the verify gate from Task 5) run `3.35.x` — releases ship on a toolchain never tested. Pin release to the same line as PR CI.

- [ ] **Step 1: Change the release Flutter version**

In `.github/workflows/release.yaml:46`:
```yaml
  FLUTTER_VERSION: "3.35.x"
```

- [ ] **Step 2: Verify alignment**

```bash
grep -h "3.3" .github/workflows/main.yaml .github/workflows/release.yaml
```
Expected: both show `3.35.x`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yaml
git commit -m "ci: align release Flutter version with PR CI (3.35.x)"
```

---

## Task 7: Resolve web cross-origin-isolation risk (H-16)

**Shape:** Config/platform. Verification = documented SAB decision + shim if required.

**Files:**
- Modify: `web/index.html`
- Modify: `.github/workflows/release.yaml` (build-web job, if self-hosting)
- Create: `web/coi-serviceworker.js` (only if shim path chosen)

**Why:** GitHub Pages cannot set `COOP`/`COEP` headers, and `index.html` ships no `coi-serviceworker`. MediaPipe GenAI's threaded/SIMD WASM (`LlmInference`, loaded `web/index.html:43-47`) generally requires `SharedArrayBuffer` / cross-origin isolation. If required, the production web build loads but fails at first inference.

- [ ] **Step 1: Determine whether SAB is required**

Check the pinned MediaPipe `@mediapipe/tasks-genai@0.10.25` and `flutter_gemma` web docs for a `SharedArrayBuffer` requirement. Record the finding (one line) in a new `docs/web-deployment.md`. Most MediaPipe GenAI builds **do** require SAB.

- [ ] **Step 2 (if SAB required): Add the coi-serviceworker shim**

Add Gohar Irfan's `coi-serviceworker` (a self-contained script that re-serves the page with COOP/COEP via a service worker) as `web/coi-serviceworker.js` (copy the minified script inline — it is MIT and dependency-free), and load it as the **first** script in `<head>` of `web/index.html`, before the flutter_gemma CDN scripts (`:37`):
```html
  <script src="coi-serviceworker.js"></script>
```
This adds cross-origin isolation on static hosts like GitHub Pages without server headers.

- [ ] **Step 3: Verify locally**

```bash
flutter build web --release --target lib/main_production.dart
```
Then serve `build/web` and open DevTools console; confirm `crossOriginIsolated === true` and `typeof SharedArrayBuffer !== 'undefined'`. Note the check command in `docs/web-deployment.md`.

- [ ] **Step 4: Commit**

```bash
git add web/index.html web/coi-serviceworker.js docs/web-deployment.md
git commit -m "fix(web): enable cross-origin isolation for MediaPipe SAB requirement"
```

---

## Task 8: Fix macOS LiteRT-LM JAR discovery + pin web JS runtime (M-24)

**Shape:** Config/CI. Verification = step targets hosted pub cache and fails loudly; web JS version reconciled.

**Files:**
- Modify: `.github/workflows/release.yaml` (Pre-build LiteRT-LM JAR step, `:252-262`)
- Modify: `web/index.html` (`:37-41` flutter_gemma CDN scripts, `:44` MediaPipe)

**Why:** M-24 has **two** parts. (a) The macOS step searches `$HOME/.pub-cache/git` but `pubspec.lock` resolves `flutter_gemma` as **hosted** 1.2.1, so `find` returns nothing and the step only warns — the `.dmg` may ship without the LiteRT-LM backend. (b) `web/index.html:37-41` loads `flutter_gemma@0.12.0` JS from jsDelivr while the Dart package is **1.2.1** (version skew), and `:44` loads `@mediapipe/tasks-genai@0.10.25` — two hard CDN runtime dependencies (blocked CDN = broken web app) plus a supply-chain surface.

- [ ] **Step 1: Point discovery at the hosted cache and fail loudly**

Replace the step body (`:253-262`) with:
```yaml
        run: |
          GEMMA_PATH=$(find $HOME/.pub-cache/hosted/pub.dev -maxdepth 1 -type d -name "flutter_gemma-*" | head -n 1)
          if [ -z "$GEMMA_PATH" ]; then
            GEMMA_PATH=$(find $HOME/.pub-cache/git -maxdepth 1 -type d -name "flutter_gemma*" | head -n 1)
          fi
          if [ -d "$GEMMA_PATH/macos/litertlm-server" ]; then
            echo "Pre-building JAR in $GEMMA_PATH..."
            cd "$GEMMA_PATH/macos/litertlm-server"
            chmod +x gradlew
            ./gradlew fatJar --no-daemon
          else
            echo "::error::flutter_gemma/macos/litertlm-server not found in pub cache ($GEMMA_PATH). macOS build would ship without the LiteRT-LM backend."
            exit 1
          fi
```

- [ ] **Step 2: Reconcile the web JS runtime version (M-24 part b)**

Determine the JS runtime version that flutter_gemma **1.2.1** expects for web (check the package's `README`/`web/` docs or its `example/web/index.html`). Update `web/index.html:37-41` to load the matching version instead of `@0.12.0`, and prefer **self-hosting** the JS assets (copy them into `web/` and reference by relative path) over the jsDelivr CDN so a blocked/unavailable CDN cannot break the app. If self-hosting the MediaPipe `@mediapipe/tasks-genai` bundle (`:44`) is impractical, at minimum pin it to the version flutter_gemma 1.2.1 targets and record the CDN dependency as a known risk in `docs/web-deployment.md` (created in Task 7). This is coordinated with Task 7's `coi-serviceworker` — both edit `web/index.html`; if Tasks 7 and 8 are done separately, rebase carefully.

- [ ] **Step 3: Verify YAML parses + web build succeeds**

```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yaml')); print('YAML OK')"
flutter build web --release --target lib/main_production.dart
```
Expected: `YAML OK`; web build completes. Serve `build/web` and confirm inference works (the reconciled runtime loads).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yaml web/index.html docs/web-deployment.md
git commit -m "ci(macos): locate flutter_gemma in hosted pub cache; pin/self-host web JS runtime"
```

---

## Task 9: Config housekeeping batch (L-6, L-25, L-28, L-29) + delete stale test output

**Shape:** Config housekeeping. Verification = `flutter pub get` + `flutter analyze` clean. Batched because each is a one-line, low-risk edit sharing one review.

**Files:**
- Modify: `pubspec.yaml` (L-6, L-29)
- Modify: `ios/Runner/Info.plist` (L-25)
- Modify: `web/index.html:22` (L-28)
- Delete: `test_output.txt` (master-plan housekeeping)

- [ ] **Step 1: Pin unpinned deps (L-6)**

In `pubspec.yaml`, replace the three `any` constraints with caret ranges matching what `pubspec.lock` currently resolves. Determine current versions first (the resolved `version:` line sits ~2 lines below each package key, so print a few lines of context):
```bash
grep -A3 -E "^  (logger|stacked_shared|path_provider_platform_interface):" pubspec.lock
```
(Read the `version: "x.y.z"` line under each package name and use `^x.y.z`.)
Then set (adjust to the resolved versions printed above), e.g.:
```yaml
  logger: ^2.4.0
  stacked_shared: ^1.4.0
```
and in `dev_dependencies`:
```yaml
  path_provider_platform_interface: ^2.1.2
```

- [ ] **Step 2: Verify EOL status of sqlite3_flutter_libs (L-29)**

`pubspec.lock:884` resolves `sqlite3_flutter_libs 0.6.0+eol`. Check pub.dev for the maintained successor. If a maintained release exists, bump the `pubspec.yaml:33` constraint; if `0.6.0+eol` is still the current recommended pin for the `sqlite3` major in use, leave it and add a one-line comment in `pubspec.yaml` recording the check date (2026-07-07). Do not guess — verify on pub.dev.

- [ ] **Step 3: Add iOS export-compliance key (L-25)**

In `ios/Runner/Info.plist`, add before `</dict>` (`:59`):
```xml
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
```
(The app uses only HTTPS/standard crypto — exempt. This stops every TestFlight upload from prompting for export compliance.)

- [ ] **Step 4: Set a real web meta description (L-28)**

In `web/index.html:22`:
```html
  <meta name="description" content="On-device, fully offline RAG assistant. Ask questions over your own documents — no data leaves your device.">
```

- [ ] **Step 5: Delete the stale test output**

```bash
git rm test_output.txt
```
(Audit: shows a pre-refactor failure superseded by today's green run; safe to delete.)

- [ ] **Step 6: Verify**

```bash
flutter pub get && flutter analyze
```
Expected: pub get resolves; analyze reports 0 errors, 0 warnings (info count unchanged or lower).

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist web/index.html
git commit -m "chore: pin deps, add iOS export-compliance key, real web description; drop stale test output"
```

---

## Phase 1 completion gate

- [ ] All 9 tasks committed.
- [ ] `flutter analyze` → 0 errors, 0 warnings.
- [ ] `flutter test` → 124 passing (Phase 1 changes no Dart logic, so the count is unchanged).
- [ ] `release.yaml` YAML parses; `verify` job precedes all builds; 7 build steps carry `--build-number`.
- [ ] Proceed to [Phase 2 — Data Integrity](2026-07-07-prod-phase2-data-integrity.md).
