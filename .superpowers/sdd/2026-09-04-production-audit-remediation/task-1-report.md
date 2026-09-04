# Task 1 Report: Platform-aware model catalog and guarded first-run downloads

## Implementation

- Added model platform and file-type metadata, including desktop-only
  `.litertlm` inference and mobile/web-only `.task` inference models.
- Filtered inference and embedding candidates by platform, GPU, RAM, and
  storage before choosing the requested tier.
- Made desktop GPU capability detection conservative and cached one capability
  read per service instance.
- Resolved device capability and recommendation services through the locator in
  startup and settings; model management uses the same registered capability
  service when no optional test provider is supplied.
- Added `DownloadPolicyService`, with injectable connectivity input, aggregate
  selected-model storage checks, fail-closed unknown connectivity, and an
  explicit consent seam.
- Added a localized custom download-consent dialog that shows both selected
  model names and formatted sizes and offers a smaller compatible selection.
- Blocked incompatible download and activation attempts with model-specific
  error state, and made missing persisted catalog IDs fall back only within the
  matching model type.

## Files changed

- App/registration/UI: `lib/app/app.dart`, `lib/app/app.locator.dart`,
  `lib/ui/setup_dialog_ui.dart`,
  `lib/ui/dialogs/download_consent_dialog.dart`, and both ARB files.
- Services: `device_capability_service.dart`, `model_config.dart`,
  `model_recommendation_service.dart`, `model_management_service.dart`, and
  new `download_policy_service.dart`.
- View models: startup and settings.
- Tests and test registration: focused catalog, capability, recommendation,
  policy, model-management, startup, and settings coverage.

Generated Linux, macOS, and Windows plugin registrant changes produced by
Flutter tooling were restored and are intentionally excluded.

## Verification

Commands run in `C:\dev\ws\flutter\offline_sync\.worktrees\production-audit-fixes`:

```text
flutter analyze
```

Result: `No issues found! (ran in 3.5s)`.

```text
flutter test test/services/model_config_test.dart \
  test/services/device_capability_service_test.dart \
  test/services/model_recommendation_service_test.dart \
  test/services/download_policy_service_test.dart \
  test/services/model_management_service_test.dart \
  test/ui/views/startup/startup_viewmodel_test.dart \
  test/ui/views/settings/settings_viewmodel_test.dart \
  test/ui/views/settings/settings_view_test.dart \
  test/ui/views/startup/startup_view_test.dart
```

Result: `00:05 +131: All tests passed!`.

```text
git diff --check
```

Result: no whitespace errors.

## Self-review against the brief

1. Catalog metadata and compatibility filtering are present; desktop picks the
   existing LiteRT-LM model, mobile/web models remain `.task`, and saved IDs
   only fall back to their own type.
2. Desktop GPU reports false by default, `requiresGpu` participates in
   compatibility checks, and locator-backed capability/recommendation services
   are used by startup and settings.
3. First-run downloads evaluate total bytes, storage, connection state, and
   explicit consent. Unknown connection state denies the request, denial does
   not mutate model state, and the smaller compatible selection is available.
4. Download and activation reject incompatible models before downloader or
   activator invocation and record model-specific errors.
5. Focused tests cover platform compatibility, desktop tiers, GPU rejection,
   storage and connection policy decisions, consent accept/deny, incompatible
   download/activation, locator-backed construction, and missing IDs.

## Concern

The full `flutter test` suite was not run after the user requested that work
stop and authorized committing after focused tests plus analysis. The focused
Task 1 suite and `flutter analyze` are green; full-suite verification remains
the only outstanding concern.

## Final round-1 fixes

- Replaced the fail-closed-only production connectivity default with a real
  `connectivity_plus` 6.1.5 provider while retaining injection. Wi-Fi and
  Ethernet are unmetered; mobile, other, satellite, and Bluetooth are treated
  as metered; no connection, VPN-only, empty results, and plugin failures remain
  unknown. A known connected result now reaches explicit consent.
- Reused flutter_gemma's `ModelFileType` in catalog metadata and passed each
  inference model's declared file type through cached activation and foreground
  installation. The injected installer seam now exposes the file type.
- Expanded recommendation coverage to all 24 supported platform-by-tier
  combinations with literal expected model IDs, tier/fallback checks, runnable
  inference file types, and compatibility assertions.
- Replaced policy UI copy returned by the service with stable reason values.
  Startup policy denials and consent reasons are localized through new English
  and Spanish ARB entries.
- Restored generated Linux, macOS, and Windows plugin registrant deltas after
  verification.

### Final verification

```text
flutter test test/services/download_policy_service_test.dart \
  test/services/model_recommendation_service_test.dart \
  test/services/model_management_service_test.dart \
  test/ui/views/startup/startup_viewmodel_test.dart \
  test/ui/views/startup/startup_view_test.dart \
  test/ui/dialogs/download_consent_dialog_test.dart
```

Result: `00:04 +133: All tests passed!`.

```text
flutter analyze
```

Result: `No issues found! (ran in 4.0s)`.

Controller verification supplied for this round:

```text
flutter test --coverage
```

Result: `385 passed, 0 failed`.

Final concern: no additional full suite was run by this fixer, per instruction;
the controller's full coverage run above is green.
