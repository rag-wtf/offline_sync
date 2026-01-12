import 'package:offline_sync/app/main_app.dart';
import 'package:offline_sync/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const MainApp());
}
