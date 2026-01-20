# **Cross-Platform System Resource Monitoring in Flutter: Architectural Analysis & Implementation**
Source: https://gemini.google.com/share/4ee478e55287

## **1\. Executive Summary**

Finding a single Flutter package to reliably detect System RAM and Storage across **all** supported platforms (Android, iOS, Web, Windows, macOS, Linux) is complex because "Monitoring" (Free Space/RAM) and "Detection" (Total Capacity) are fundamentally different operations with different platform constraints.

* **For Static Detection (Device Specs):** Use **device\_info\_plus** (RAM) combined with **disk\_usage** (Storage).  
* **For Dynamic Monitoring (Real-time Usage):** Use a **Composite Architecture** combining **system\_info2** (Native Memory), **disk\_usage** (Native Storage), and **package:web** (Web Interop).

There is **no single package** that covers dynamic monitoring for all 6 platforms perfectly due to the browser's sandbox security model. The most stable solution requires a modular approach.

## **2\. The Core Distinction: Detection vs. Monitoring**

Before selecting a package, you must define your goal. The technical requirements for these two goals are often mutually exclusive on modern operating systems.

| Feature | Static Detection (Capacity) | Dynamic Monitoring (Usage) |
| :---- | :---- | :---- |
| **Goal** | "Is this a high-end device?" | "Can I allocate 50MB right now?" |
| **Metrics** | Total RAM, Total Disk Size | Free RAM, Available Disk Space |
| **Frequency** | Once (at app startup) | Frequent (polling or event-based) |
| **Web Limit** | Approximate (Buckets: 4GB, 8GB) | **Impossible** (Blocked for privacy) |
| **iOS Limit** | Accurate | **Misleading** (due to compression) |

## **3\. Recommended Packages & Architecture**

### **3.1 The "All-Platform" Storage Solution: disk\_usage**

Unlike many abandoned plugins, **disk\_usage** is the current best-in-class solution for storage because it supports all 5 native platforms (Mobile \+ Desktop).

* **Platforms:** Android, iOS, macOS, Windows, Linux.  
* **Why it wins:** It supersedes disk\_space\_plus (Mobile only) and universal\_disk\_space (Desktop only). It correctly handles StatFs on Android and statvfs on Linux/macOS.  
* **Web Gap:** It does not support Web. You **must** use the Web Interop layer (provided in Section 4\) to handle browser quotas.

### **3.2 The Native Memory Specialist: system\_info2**

For real-time memory monitoring on native platforms, **system\_info2** is the superior choice over system\_info\_plus.

* **Platforms:** Android, iOS, Windows, macOS, Linux.  
* **Why it wins:** It uses **Dart FFI** (Foreign Function Interface) on desktop platforms, allowing it to read kernel statistics directly without the overhead of Platform Channels. This makes it efficient enough for real-time polling.  
* **Critical Warning (iOS):** iOS uses **Compressed Memory**. "Free RAM" is often near zero because iOS keeps apps in memory but compresses them. **Do not** use getFreePhysicalMemory() to prevent crashes on iOS. Instead, rely on TotalPhysicalMemory to set your cache limits (e.g., "If Total \> 4GB, cache size \= 500MB").

### **3.3 The Static Spec Standard: device\_info\_plus**

If you only need **Total RAM** to categorize the device (e.g., for analytics), stick to the standard community package.

* **Platforms:** All 6 (including Web).  
* **Usage:** It provides totalMemory on Android/Windows and physicalMemory on iOS.  
* **Web Caveat:** On Web, it returns deviceMemory which is an approximation (e.g., 2, 4, 8\) to prevent fingerprinting.

## **4\. Implementation: The Composite Architecture**

To achieve true "All Platform" reliability, you should implement this ResourceMonitor class. It abstracts the differences between Native and Web logic using conditional imports.

### **Step 1: Add Dependencies**

YAML

dependencies:  
  disk\_usage: ^1.0.0  
  system\_info2: ^4.1.0  
  device\_info\_plus: ^12.3.0 \# Optional, for static specs  
  web: ^1.1.1               \# Required for Wasm-compatible Web support

### **Step 2: The Unified Interface**

Create a contract that your app will use.

Dart

abstract class ResourceMonitor {  
  /// Total capacity in bytes.  
  Future\<int?\> getTotalStorage();  
    
  /// Available space in bytes. (On Web, this is remaining Quota).  
  Future\<int?\> getFreeStorage();  
    
  /// Total physical RAM in bytes. (Approximate on Web).  
  Future\<int?\> getTotalMemory();  
    
  /// Free physical RAM in bytes. (Returns null on Web).  
  Future\<int?\> getFreeMemory();  
}

### **Step 3: Native Implementation (Mobile/Desktop)**

Create monitor\_native.dart. This uses the specialized packages.

Dart

import 'package:disk\_usage/disk\_usage.dart';  
import 'package:system\_info2/system\_info2.dart';  
import 'resource\_monitor\_interface.dart'; // Your abstract class

class ResourceMonitorImpl implements ResourceMonitor {  
  @override  
  Future\<int?\> getTotalStorage() async {  
    // DiskUsage handles permissions internally for app-scoped storage  
    return await DiskUsage.space(DiskSpaceType.total);  
  }

  @override  
  Future\<int?\> getFreeStorage() async {  
    return await DiskUsage.space(DiskSpaceType.free);  
  }

  @override  
  Future\<int?\> getTotalMemory() async {  
    // SysInfo uses FFI for high performance  
    return SysInfo.getTotalPhysicalMemory();  
  }

  @override  
  Future\<int?\> getFreeMemory() async {  
    return SysInfo.getFreePhysicalMemory();  
  }  
}

### **Step 4: Web Implementation (Wasm Compatible)**

Create monitor\_web.dart. This replaces the deprecated dart:html with modern package:web.

Dart

import 'dart:js\_interop';  
import 'package:web/web.dart' as web;  
import 'resource\_monitor\_interface.dart';

class ResourceMonitorImpl implements ResourceMonitor {  
  @override  
  Future\<int?\> getTotalMemory() async {  
    // navigator.deviceMemory returns GiB (e.g., 2, 4, 8).   
    // It is approximate for privacy.  
    final nav \= web.window.navigator;  
    if (nav.hasProperty('deviceMemory'.toJS).toDart) {  
       final memGiB \= (nav as dynamic).deviceMemory as double?;  
       if (memGiB\!= null) {  
         return (memGiB \* 1024 \* 1024 \* 1024).toInt();  
       }  
    }  
    return null;   
  }

  @override  
  Future\<int?\> getFreeMemory() async {  
    // Browsers block access to "Free RAM" to prevent user tracking.  
    return null;   
  }

  @override  
  Future\<int?\> getFreeStorage() async {  
    // Uses StorageManager API to check Quota  
    if (web.window.navigator.storage\!= null) {  
      final estimate \= await web.window.navigator.storage\!.estimate().toDart;  
      final quota \= estimate.quota?.toInt()?? 0;  
      final usage \= estimate.usage?.toInt()?? 0;  
      return quota \- usage;  
    }  
    return null;  
  }

  @override  
  Future\<int?\> getTotalStorage() async {  
    if (web.window.navigator.storage\!= null) {  
      final estimate \= await web.window.navigator.storage\!.estimate().toDart;  
      return estimate.quota?.toInt();  
    }  
    return null;  
  }  
}

### **Step 5: The Factory Constructor**

In your main class file, use conditional imports to load the correct file.

Dart

import 'resource\_monitor\_interface.dart';  
import 'monitor\_native.dart' if (dart.library.js\_interop) 'monitor\_web.dart';

ResourceMonitor getResourceMonitor() \=\> ResourceMonitorImpl();

## **5\. Critical Reliability Notes**

1. **Android Permissions:** disk\_usage works reliably for the app's internal sandbox. If you try to query the *root* of the SD card (/storage/emulated/0), it will fail on Android 10+ unless you have MANAGE\_EXTERNAL\_STORAGE permission. Stick to the default path (app sandbox) for 100% reliability.  
2. **iOS Jetsam:** iOS apps are terminated based on "Memory Pressure," not just raw "Free Memory." Even if getFreeMemory() returns 200MB, the OS might kill your app if you allocate 50MB quickly. **Strategy:** Use WidgetsBindingObserver.didHaveMemoryPressure to listen for OS warnings instead of polling free RAM.  
3. **Web Accuracy:** deviceMemory on Web is deliberately inaccurate (rounded to powers of 2). Never use it for exact calculations; use it only to switch between "High Quality" (e.g., \>4GB) and "Lite" (e.g., \<4GB) modes.  
4. **Desktop Sandboxing:** On macOS, disk\_usage requires the **App Sandbox entitlement** com.apple.security.files.user-selected.read-only if you allow users to pick a folder to check space.

## **6\. Conclusion**

For **Stability and Reliability** across all 6 platforms:

1. **Use the Composite Architecture:** Do not look for a single "magic" package.  
2. **Storage:** Rely on **disk\_usage** for Native and **StorageManager** for Web.  
3. **Memory:** Rely on **system\_info2** for Native and **deviceMemory** for Web.  
4. **Logic:** Design your app to handle null returns gracefully (especially for Web memory), treating them as "Standard/Low End" device profiles.