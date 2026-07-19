import 'package:flutter/material.dart';

import 'core/ui/app_theme.dart';
import 'features/shell/home_shell.dart';

class EasyTrackApp extends StatelessWidget {
  const EasyTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
