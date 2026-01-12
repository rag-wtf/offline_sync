import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/app/main_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();
  runApp(const MainApp());
}
