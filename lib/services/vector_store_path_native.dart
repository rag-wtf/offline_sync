import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _storageChannel = MethodChannel('offline_sync/storage');

/// Platform-specific database path helper for native platforms.
/// Uses path_provider to get the application support directory.
/// Automatically migrates any legacy database found in documents directory.
Future<String> getDatabasePath(String filename) async {
  final supportDir = await getApplicationSupportDirectory();
  final targetPath = p.join(supportDir.path, filename);
  await _excludeFromBackup(supportDir.path);

  try {
    final docsDir = await getApplicationDocumentsDirectory();
    await _excludeFromBackup(docsDir.path);
    final legacyPath = p.join(docsDir.path, filename);
    final legacyFile = File(legacyPath);
    final targetFile = File(targetPath);

    if (legacyFile.existsSync() && !targetFile.existsSync()) {
      if (!supportDir.existsSync()) {
        supportDir.createSync(recursive: true);
      }
      legacyFile
        ..copySync(targetPath)
        ..deleteSync();
    }
  } on Object catch (_) {}

  return targetPath;
}

Future<void> _excludeFromBackup(String path) async {
  try {
    await _storageChannel.invokeMethod<void>('excludeFromBackup', path);
  } on MissingPluginException {
    // Platforms without the native hook continue with local storage.
  } on PlatformException {
    // Backup exclusion must not prevent local storage initialization.
  }
}
