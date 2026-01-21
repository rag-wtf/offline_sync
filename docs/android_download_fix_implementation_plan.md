# Fork flutter_gemma for UIDT Download Fix

## Problem
Android 16 ignores the `important-while-foreground` flag:
```
W/JobInfo: Requested important-while-foreground flag for job4 is ignored
```

Foreground mode is insufficient. UIDT (User Initiated Data Transfer) is required.

## UIDT Requirements
| Requirement | Current State | Needed |
|-------------|---------------|--------|
| priority | 10 | **0** |
| notification | ✓ Configured | ✓ |
| Android 14+ | ✓ User has 16 | ✓ |

## Solution: Fork flutter_gemma

### Step 1: Fork the Repository
```bash
# Fork https://github.com/nickmeinhold/flutter_gemma to your GitHub
# Then clone locally
git clone https://github.com/limcheekin/flutter_gemma.git
```

### Step 2: Modify SmartDownloader
In `lib/mobile/smart_downloader.dart`, line ~203:

```diff
- priority: 10,
+ priority: 0, // Use UIDT on Android 14+ to prevent WorkManager cancellation
```

### Step 3: Update pubspec.yaml Dependency
```yaml
dependencies:
  flutter_gemma:
    git:
      url: https://github.com/limcheekin/flutter_gemma.git
      ref: main  # or your branch name
```

### Step 4: Remove pub.dev version
```bash
cd /media/limcheekin/My\ Passport/ws/rag.wtf/offline_sync
flutter pub get
```

## Why This Works
UIDT bypasses WorkManager's regular job scheduling and uses a dedicated User Initiated Data Transfer service that:
- Does NOT have a 9-minute timeout
- Is NOT cancelled by network state changes
- Is designed for large file downloads

## Alternative: Submit PR to flutter_gemma
Consider submitting a PR to the original repo to make priority configurable.
