import 'package:flutter/material.dart';

/// Colors used to distinguish the three macronutrients throughout the app.
///
/// These are fixed rather than derived from the theme because a user learns
/// "protein is the teal one" and that association must not shift between light
/// and dark mode or between screens.
abstract final class MacroColors {
  static const Color protein = Color(0xFF00897B); // teal
  static const Color carbs = Color(0xFFF9A825); // amber
  static const Color fat = Color(0xFF8E24AA); // purple
  static const Color water = Color(0xFF1E88E5); // blue
  static const Color activity = Color(0xFF43A047); // green
}

abstract final class AppTheme {
  static const Color _seed = Color(0xFF2E7D32);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // The diary is a dense list of numbers; tighter visual density fits more
      // of a day on screen without scrolling.
      visualDensity: VisualDensity.compact,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
