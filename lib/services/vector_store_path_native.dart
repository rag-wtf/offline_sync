import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Platform-specific database path helper for native platforms.
/// Uses path_provider to get the application support directory.
/// Automatically migrates any legacy database found in documents directory.
Future<String> getDatabasePath(String filename) async {
  final supportDir = await getApplicationSupportDirectory();
  await _excludeFromBackup(supportDir);
  final targetPath = p.join(supportDir.path, filename);

  try {
    final docsDir = await getApplicationDocumentsDirectory();
    await _excludeFromBackup(docsDir);
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

Future<void> _excludeFromBackup(Directory directory) async {
  try {
    await const MethodChannel('offline_sync/storage').invokeMethod<void>(
      'excludeFromBackup',
      directory.path,
    );
  } on MissingPluginException {
    // Desktop/Linux implementations without a cloud-backup concept need no
    // action. iOS/macOS implement the channel below.
  } on PlatformException {
    // A backup flag is defense-in-depth; failure must not prevent local use.
  }
}
