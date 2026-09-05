import 'package:offline_sync/bootstrap_web.dart' as bootstrap;

Future<void> flushDatabase() => bootstrap.flushSqlite();
