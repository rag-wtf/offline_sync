import 'package:flutter/material.dart';
import 'package:offline_sync/app/app.router.dart';
import 'package:stacked_services/stacked_services.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline RAG Sync',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      initialRoute: Routes.startupView,
      onGenerateRoute: StackedRouter().onGenerateRoute,
      navigatorKey: StackedService.navigatorKey,
    );
  }
}
