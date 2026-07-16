# Android 16 Download Failure Investigation

## Issue
Model downloads fail at 0-3% on Android 16 due to WorkManager cancelling jobs when WiFi network state changes.

## Root Cause Analysis

### 1. Network State Tracking
Android's `NetworkStateTracker` detects WiFi capability changes (signal strength, bandwidth) and triggers `onStopJob`:
```
W/JobService: onNetworkChanged() not implemented
D/WM-SystemJobService: onStopJob for WorkGenerationalId...
I/TaskRunner: JobCancellationException: Job was cancelled
```

### 2. Foreground Mode Ignored on Android 16
Even with foreground mode configured, Android 16 ignores the flag:
```
W/JobInfo: Requested important-while-foreground flag for job4 is ignored
```

### 3. Solution: UIDT (User Initiated Data Transfer)
UIDT is a special Android 14+ service that:
- Does NOT have 9-minute timeout
- Is NOT cancelled by network state changes
- Requires `priority: 0` in DownloadTask

## Changes Made

### 1. AndroidManifest.xml
Added UIDT and foreground service permissions/declarations:
```xml
<uses-permission android:name="android.permission.RUN_USER_INITIATED_JOBS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />

<service
    android:name="com.bbflight.background_downloader.UIDTJobService"
    android:permission="android.permission.BIND_JOB_SERVICE"
    android:exported="true"
    android:foregroundServiceType="dataSync" />
```

### 2. pubspec.yaml
Added `background_downloader: ^9.5.2` as direct dependency.

### 3. bootstrap.dart
Configured FileDownloader with foreground mode and notifications:
```dart
if (defaultTargetPlatform == TargetPlatform.android) {
  await FileDownloader().configure(
    androidConfig: (Config.runInForegroundIfFileLargerThan, 0),
  );
  FileDownloader().configureNotificationForGroup(
    'smart_downloads',
    running: const TaskNotification('Downloading Model', '{displayName} - {progress}%'),
    progressBar: true,
  );
}
```

## Remaining Fix Required

### Fork flutter_gemma
The `SmartDownloader` in `flutter_gemma` uses `priority: 10`. For UIDT to work, it needs `priority: 0`.

In `lib/mobile/smart_downloader.dart`, line ~203:
```dart
// Change from
priority: 10,
// To
priority: 0,
```

Then update pubspec.yaml:
```yaml
dependencies:
  flutter_gemma:
    git:
      url: https://github.com/YOUR_USERNAME/flutter_gemma.git
```

## UIDT Requirements Summary

| Requirement | Status |
|-------------|--------|
| `RUN_USER_INITIATED_JOBS` permission | ✅ Added |
| `UIDTJobService` declaration | ✅ Added |
| Notification configured | ✅ Added |
| `priority: 0` in DownloadTask | ❌ Requires flutter_gemma fork |
