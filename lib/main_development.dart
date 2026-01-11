import 'package:offline_sync/app/app.dart';
import 'package:offline_sync/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
