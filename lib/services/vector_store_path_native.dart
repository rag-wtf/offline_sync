import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Platform-specific database path helper for native platforms.
/// Uses path_provider to get the application documents directory.
Future<String> getDatabasePath(String filename) async {
  final appDir = await getApplicationDocumentsDirectory();
  return p.join(appDir.path, filename);
}
