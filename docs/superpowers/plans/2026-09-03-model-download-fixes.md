# Model Download Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix model downloading on Android by configuring the foreground service in the manifest and `FlutterGemma`, adding model repo URL derivation, classifying gated-repo access errors with actionable guidance, and updating user-facing token dialogues.

**Architecture:** 
1. Ensure the Android manifest declares the `tools` namespace and merges `foregroundServiceType="dataSync"` onto WorkManager's `SystemForegroundService`.
2. Pass `foreground: true` to `FlutterGemma.installModel().fromNetwork()` during downloads in `ModelManagementService` so transfers are not terminated by WorkManager's 9-minute cap.
3. Derive `repoPage` from `modelUrl` on `ModelDefinition` and `ModelInfo` to prevent repo drift.
4. Implement `download_failure.dart` to identify gated repository rejections (401/403) and provide clear 3-point guidance.
5. Update `StartupViewModel` and `TokenInputDialog` to guide users on accepting model terms and granting gated-repo token scopes.

**Tech Stack:** Flutter 3.44+, Dart 3.12+, `flutter_gemma` 1.7.0, `background_downloader` 9.5.9, `stacked`.

**Spec:** `C:\dev\ws\flutter\yi\docs\model-download-fixes.md`

## Global Constraints

- Working tree: `C:\dev\ws\flutter\offline_sync\.worktrees\model-download-fixes`
- All 337 existing tests must pass with zero regressions.
- Pass `foreground: true` ONLY on actual download transfers (`ModelManagementService._performDownload`), NEVER on cached model re-registration (`_activateInferenceModel`).
- Model repository URLs must be derived dynamically from `modelUrl` rather than duplicated as hardcoded strings.
- Strictly follow TDD: write the failing test first, verify failure, write minimal implementation, verify pass, and commit.

---

### Task 1: Android Manifest Foreground Service Merge

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: Existing permissions in `AndroidManifest.xml`
- Produces: Correct Android manifest with `xmlns:tools` and `tools:node="merge"` on `SystemForegroundService`

- [ ] **Step 1: Check existing manifest service declaration**

Inspect `android/app/src/main/AndroidManifest.xml` to verify missing `xmlns:tools` and missing `tools:node="merge"` on `SystemForegroundService`.

- [ ] **Step 2: Update AndroidManifest.xml**

Update `<manifest>` root tag to include `xmlns:tools="http://schemas.android.com/tools"`:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
```

Update `SystemForegroundService` inside `<application>`:
```xml
        <!-- Foreground service for long-running downloads -->
        <service
            android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync"
            tools:node="merge" />
```

- [ ] **Step 3: Verify XML syntax and run flutter analyze**

Run: `flutter analyze`
Expected: No analysis errors.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "fix(android): add tools namespace and merge SystemForegroundService"
```

---

### Task 2: Model Repo Page Derivation

**Files:**
- Modify: `lib/services/model_config.dart`
- Modify: `lib/services/model_management_service.dart`
- Test: `test/services/model_config_test.dart`

**Interfaces:**
- Consumes: `ModelDefinition.modelUrl` and `ModelInfo.url`
- Produces: `String get repoPage` on `ModelDefinition` and `ModelInfo`

- [ ] **Step 1: Write failing unit test for repoPage**

Add tests to `test/services/model_config_test.dart`:
```dart
    test('repoPage derives the Hugging Face repo page from modelUrl', () {
      for (final model in ModelConfig.allModels) {
        expect(model.repoPage, startsWith('https://huggingface.co/'));
        expect(model.modelUrl, startsWith(model.repoPage));
        final uri = Uri.parse(model.repoPage);
        expect(uri.pathSegments.length, 2,
            reason: '${model.id} repoPage should have org/repo path');
      }
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/model_config_test.dart`
Expected: FAIL (getter `repoPage` isn't defined).

- [ ] **Step 3: Implement `repoPage` on ModelDefinition and ModelInfo**

In `lib/services/model_config.dart`, add to `ModelDefinition`:
```dart
  /// The Hugging Face repo page for [modelUrl].
  String get repoPage {
    final uri = Uri.parse(modelUrl);
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      return 'https://huggingface.co/${segments[0]}/${segments[1]}';
    }
    return modelUrl;
  }
```

In `lib/services/model_management_service.dart`, add to `ModelInfo`:
```dart
  /// The Hugging Face repo page for [url].
  String get repoPage {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      return 'https://huggingface.co/${segments[0]}/${segments[1]}';
    }
    return url;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/model_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/model_config.dart lib/services/model_management_service.dart test/services/model_config_test.dart
git commit -m "feat(models): derive repoPage from modelUrl on ModelDefinition and ModelInfo"
```

---

### Task 3: Download Failure Classification Utility

**Files:**
- Create: `lib/utils/download_failure.dart`
- Test: `test/utils/download_failure_test.dart`

**Interfaces:**
- Consumes: `Object error`, `String repoPage`
- Produces: `bool isGatedAccessError(Object error)`, `String describeDownloadFailure(Object error, {required String repoPage})`

- [ ] **Step 1: Write failing unit tests for download failure utility**

Create `test/utils/download_failure_test.dart`:
```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/utils/download_failure.dart';

void main() {
  const repo = 'https://huggingface.co/litert-community/Gemma3-1B-IT';

  group('DownloadFailure', () {
    test('classifies typed 401/403 from flutter_gemma as gated access error', () {
      expect(
        isGatedAccessError(const DownloadException(DownloadError.unauthorized())),
        isTrue,
      );
      expect(
        isGatedAccessError(const DownloadException(DownloadError.forbidden())),
        isTrue,
      );
      expect(
        isGatedAccessError(const DownloadException(DownloadError.network('down'))),
        isFalse,
      );
    });

    test('classifies string errors with auth and gate status', () {
      expect(
        isGatedAccessError(Exception('HTTP 401 Unauthorized: Access to model is restricted')),
        isTrue,
      );
      expect(
        isGatedAccessError(Exception('403 Forbidden: GatedRepo access denied')),
        isTrue,
      );
      expect(
        isGatedAccessError(Exception('proxy returned 403 to the CDN')),
        isFalse,
      );
    });

    test('describeDownloadFailure provides 3-step advice for gated error', () {
      final message = describeDownloadFailure(
        const DownloadException(DownloadError.forbidden()),
        repoPage: repo,
      );
      expect(message, contains(repo));
      expect(message, contains('Check all three:'));
      expect(message, contains('accepted the licence on $repo'));
      expect(message, contains('token belongs to the same account'));
      expect(message, contains('Read access to the contents of all public gated repos'));
    });

    test('describeDownloadFailure passes through non-gated error verbatim', () {
      final message = describeDownloadFailure(
        Exception('disk full'),
        repoPage: repo,
      );
      expect(message, 'The download failed: Exception: disk full');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/download_failure_test.dart`
Expected: FAIL (`download_failure.dart` does not exist).

- [ ] **Step 3: Implement `download_failure.dart`**

Create `lib/utils/download_failure.dart`:
```dart
import 'package:flutter_gemma/flutter_gemma.dart';

/// Whether [error] is Hugging Face refusing the request for auth reasons:
/// no token, a token without the gated-repo scope, or a licence the account
/// has not accepted on the repo being downloaded.
bool isGatedAccessError(Object error) {
  if (error is DownloadException) {
    return switch (error.error) {
      UnauthorizedError() || ForbiddenError() => true,
      _ => false,
    };
  }

  final message = error.toString().toLowerCase();
  final hasAuthStatus = message.contains('401') ||
      message.contains('403') ||
      message.contains('unauthorized') ||
      message.contains('forbidden');
  final looksGated = message.contains('gated') ||
      message.contains('restricted') ||
      message.contains('authentication required') ||
      message.contains('authenticated') ||
      message.contains('access denied');
  return hasAuthStatus && looksGated;
}

/// A message the user can act on.
String describeDownloadFailure(Object error, {required String repoPage}) {
  if (!isGatedAccessError(error)) return 'The download failed: $error';
  return 'Hugging Face refused the download. Check all three:\n'
      '1. You accepted the licence on $repoPage — accepting it on another '
      'Gemma repo does not count.\n'
      '2. The token belongs to the same account that accepted it.\n'
      '3. A fine-grained token also needs "Read access to the contents of all '
      'public gated repos you can access".';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/download_failure_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/download_failure.dart test/utils/download_failure_test.dart
git commit -m "feat: add download failure classification utility for gated repos"
```

---

### Task 4: Foreground Mode and Error Handling in ModelManagementService

**Files:**
- Modify: `lib/services/model_management_service.dart:365-485`
- Test: `test/services/model_management_service_test.dart`

**Interfaces:**
- Consumes: `download_failure.dart`, `ModelInfo.repoPage`, `FlutterGemma.installModel`
- Produces: `foreground: true` on network downloads, descriptive gated access errors stored on `ModelInfo.errorMessage` and emitted to status controller

- [ ] **Step 1: Write failing test for gated error handling in ModelManagementService**

Add tests to `test/services/model_management_service_test.dart` verifying that when a download fails with a 401 or gated access error:
1. `model.errorMessage` contains `describeDownloadFailure` output naming `model.repoPage`.
2. The error added to `modelStatusStream` has the actionable message.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/model_management_service_test.dart`
Expected: FAIL.

- [ ] **Step 3: Update `_performDownload` in ModelManagementService**

In `lib/services/model_management_service.dart`:
1. Import `package:offline_sync/utils/download_failure.dart`.
2. At line 375, pass `foreground: true`:
```dart
          await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
          ).fromNetwork(
            downloadUrl,
            token: token,
            foreground: true,
          ).withProgress((progress) {
            log('Download progress for ${model.id}: $progress%');
            model.progress = progress / 100.0;
            _notify();
          }).install();
```
3. In the catch block:
```dart
    } on Exception catch (e) {
      log('Download failed for ${model.id}: $e');
      LoggingService.debug('Download failed for ${model.id}: $e');
      model.status = ModelStatus.error;

      if (isGatedAccessError(e) || e is AuthenticationRequiredException || e.toString().contains('401')) {
        final description = describeDownloadFailure(e, repoPage: model.repoPage);
        model.errorMessage = description;
        _statusController.addError(
          AuthenticationRequiredException(description),
        );
      } else {
        model.errorMessage = e.toString();
        _statusController.addError('Download error: $e');
      }
      _notify();
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/model_management_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/model_management_service.dart test/services/model_management_service_test.dart
git commit -m "fix(models): pass foreground: true on installModel and format gated repo errors"
```

---

### Task 5: UI Guidance Updates for Gated Model Downloads

**Files:**
- Modify: `lib/ui/dialogs/token_input_dialog.dart`
- Modify: `lib/ui/views/startup/startup_viewmodel.dart:75-100`
- Test: `test/ui/dialogs/token_input_dialog_test.dart`
- Test: `test/ui/views/startup/startup_viewmodel_test.dart`

**Interfaces:**
- Consumes: `isGatedAccessError`, `TokenInputDialog(repoPage:, modelName:)`
- Produces: Enhanced `TokenInputDialog` UI showing gated token requirements and optional repo link, and `StartupViewModel` passing gated descriptions to UI

- [ ] **Step 1: Write failing tests for TokenInputDialog and StartupViewModel**

In `test/ui/dialogs/token_input_dialog_test.dart`, add a test that verifies the dialog displays the gated repo token note:
```dart
  testWidgets('displays note about fine-grained gated repository token permission', (tester) async {
    await openDialog(tester, buildSubject());
    expect(
      find.textContaining('public gated repos'),
      findsOneWidget,
    );
  });

  testWidgets('displays repo link when repoPage is provided', (tester) async {
    await openDialog(
      tester,
      MaterialApp(
        home: Scaffold(
          body: TokenInputDialog(
            repoPage: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
            modelName: 'Gemma 3 1B IT',
          ),
        ),
      ),
    );
    expect(find.textContaining('litert-community/Gemma3-1B-IT'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/dialogs/token_input_dialog_test.dart`
Expected: FAIL.

- [ ] **Step 3: Update `TokenInputDialog` and `StartupViewModel`**

In `lib/ui/dialogs/token_input_dialog.dart`:
- Add optional parameters `final String? repoPage;` and `final String? modelName;` to `TokenInputDialog`.
- Update text description:
  - If `repoPage != null`: display prompt to accept terms at `repoPage`.
  - Add text note: `A fine-grained token also needs "Read access to the contents of all public gated repos you can access".`

In `lib/ui/views/startup/startup_viewmodel.dart`:
- Import `package:offline_sync/utils/download_failure.dart`.
- In `runStartupLogic` error handling (around lines 79-96):
  - Check for `has401Error = error.any((m) => isGatedAccessError(m.errorMessage ?? '') || (m.errorMessage?.contains('401') ?? false) || (m.errorMessage?.contains('AuthenticationRequiredException') ?? false));`
  - If true, display the error message from the failed model or `Authentication Required`.

- [ ] **Step 4: Run tests to verify they pass**

Run:
`flutter test test/ui/dialogs/token_input_dialog_test.dart`
`flutter test test/ui/views/startup/startup_viewmodel_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests pass (>= 337 tests, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/dialogs/token_input_dialog.dart lib/ui/views/startup/startup_viewmodel.dart test/ui/dialogs/token_input_dialog_test.dart test/ui/views/startup/startup_viewmodel_test.dart
git commit -m "feat(ui): update token input dialog and startup view for gated repo guidance"
```
