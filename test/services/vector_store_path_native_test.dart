import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync/services/vector_store_path_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  MockPathProviderPlatform({
    required this.supportPath,
    required this.documentsPath,
  });

  final String supportPath;
  final String documentsPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory supportDir;
  late Directory docsDir;
  final calls = <MethodCall>[];
  var throwMissingPlugin = false;
  var throwPlatformException = false;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'vector_store_path_test_',
    );
    supportDir = Directory(p.join(tempDir.path, 'support'))
      ..createSync(recursive: true);
    docsDir = Directory(p.join(tempDir.path, 'docs'))
      ..createSync(recursive: true);

    PathProviderPlatform.instance = MockPathProviderPlatform(
      supportPath: supportDir.path,
      documentsPath: docsDir.path,
    );

    calls.clear();
    throwMissingPlugin = false;
    throwPlatformException = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('offline_sync/storage'),
          (call) async {
            calls.add(call);
            if (throwMissingPlugin) {
              throw MissingPluginException();
            }
            if (throwPlatformException) {
              throw PlatformException(
                code: 'TEST_ERROR',
                message: 'Test platform error',
              );
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('offline_sync/storage'),
          null,
        );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('returns target path and invokes backup exclusion', () async {
    final path = await getDatabasePath('test.db');
    expect(path, p.join(supportDir.path, 'test.db'));
    expect(calls.length, 2);
    expect(calls[0].method, 'excludeFromBackup');
    expect(calls[0].arguments, supportDir.path);
    expect(calls[1].method, 'excludeFromBackup');
    expect(calls[1].arguments, docsDir.path);
  });

  test(
    'migrates legacy database from documents to support directory',
    () async {
      final legacyDb = File(p.join(docsDir.path, 'legacy.db'))
        ..writeAsStringSync('dummy content');
      final targetDb = File(p.join(supportDir.path, 'legacy.db'));

      expect(legacyDb.existsSync(), isTrue);
      expect(targetDb.existsSync(), isFalse);

      final path = await getDatabasePath('legacy.db');
      expect(path, targetDb.path);
      expect(targetDb.existsSync(), isTrue);
      expect(legacyDb.existsSync(), isFalse);
      expect(targetDb.readAsStringSync(), 'dummy content');
    },
  );

  test('handles MissingPluginException silently', () async {
    throwMissingPlugin = true;
    final path = await getDatabasePath('plugin_missing.db');
    expect(path, p.join(supportDir.path, 'plugin_missing.db'));
  });

  test('handles PlatformException silently', () async {
    throwPlatformException = true;
    final path = await getDatabasePath('platform_err.db');
    expect(path, p.join(supportDir.path, 'platform_err.db'));
  });
}
