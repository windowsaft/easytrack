import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/ui/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'l10n/app_localizations.dart';

class EasyTrackApp extends ConsumerWidget {
  const EasyTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The active language, driven by the user's choice (or the device default).
    // Changing it here rebuilds the whole tree, so every translated string and
    // every DateFormat re-renders in the new language.
    final locale = ref.watch(localeControllerProvider);

    return MaterialApp(
      title: 'EasyTrack',
      debugShowCheckedModeBanner: false,
      // Dark only. The design is a single high-contrast dark direction; a
      // light variant would be a second design, not a theme switch.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      locale: locale,
      // Both the app's own strings and Flutter's built-in widget translations;
      // AppLocalizations.localizationsDelegates already bundles the three Global
      // delegates alongside its own.
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const SplashScreen(),
    );
  }
}
