import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'navigation/app_shell.dart';
import 'theme/commride_theme.dart';

class CommRideApp extends StatelessWidget {
  const CommRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AppConfig config = AppConfig.fromEnvironment();

    return MaterialApp(
      title: 'CommRide',
      debugShowCheckedModeBanner: config.environment != AppEnvironment.production,
      theme: CommRideTheme.light(),
      home: AppShell(config: config),
    );
  }
}
