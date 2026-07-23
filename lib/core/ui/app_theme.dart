import 'package:flutter/material.dart';

/// Design tokens for the "Bold" direction (design handoff option 2b).
///
/// The palette is fixed rather than derived from a [ColorScheme] seed: the
/// design specifies exact hex values, and a seeded scheme would quantise them
/// into tonal palettes that drift away from the handoff on every Flutter
/// upgrade. Light mode is deliberately absent — the design is dark-only, and a
/// half-translated light variant would look broken rather than adaptive.
abstract final class AppColors {
  static const bg = Color(0xFF0C0D0A); // screen background
  static const surface = Color(0xFF15170F); // cards, list rows
  static const surfaceAlt = Color(0xFF22251A); // tile icons, gauge track
  static const surfaceAlt2 = Color(0xFF1D2015); // empty water bars
  static const bar = Color(0xFF12140C); // bottom action bars, keypad blanks
  static const selectedRow = Color(0xFF191C11); // row with a lime left border

  static const stroke = Color(0xFF22251A); // hairlines, bar top borders
  static const strokeDashed = Color(0xFF2C3020); // dashed and outlined borders
  static const strokeButton = Color(0xFF2C2F22); // header icon buttons
  static const chevron = Color(0xFF4A4F3E); // trailing chevrons
  static const dragHint = Color(0xFF3F4436); // drag_indicator on swipe rows

  static const lime = Color(0xFFC6FF3A); // primary accent
  static const brandGreen = Color(0xFF0E3B23); // launch mark + icon backdrop
  static const coral = Color(0xFFFF5A3C); // burned calories

  static const carbs = Color(0xFFF2A93B);

  /// Deliberately the same hex as [coral]. The handoff assigns one value to
  /// both protein and burned calories; they never share a surface, so the
  /// collision is not ambiguous in practice.
  static const protein = Color(0xFFFF5A3C);
  static const fat = Color(0xFF7C9CFF);
  static const water = Color(0xFF3FB6E6);

  /// Ballaststoffe. Its own line on the nutrient sheet — not a "davon" under
  /// carbohydrate — so it carries a dot like the other top-level nutrients. A
  /// muted plant green, kept clear of the neon lime accent and the cyan water.
  static const fiber = Color(0xFF5FB98E);

  static const textHi = Color(0xFFFFFFFF);
  static const text = Color(0xFFF2F3EC);
  static const textBright = Color(0xFFC9CDBE); // section headers, legend labels
  static const textMute = Color(0xFF8A8F7C);
  static const textMute2 = Color(0xFF9AA088); // inactive chip labels
  static const textFaint = Color(0xFF6A7058);
  static const textFaint2 = Color(0xFF7A7F6C); // row subtitles
  static const textUnit = Color(0xFF6F7460); // "/210" suffixes
  static const navInactive = Color(0xFF5C6150);
}

/// Corner radii. Cards and list rows are square (0) by design — that squareness
/// is most of what makes the direction read as "bold", so it is not a default
/// to be overridden per widget.
abstract final class AppRadii {
  static const iconButton = 14.0; // header buttons, search field
  static const chip = 12.0; // activity type chips
  static const tab = 11.0; // search tab pills
  static const tile = 10.0; // 42px food tile icons, add/check buttons
  static const button = 14.0; // primary and outlined buttons
  static const fab = 16.0; // centre nav button
  static const toggle = 13.0; // 44x26 switch track
}

/// The two-family type scale.
///
/// Anton carries every numeral and section heading; Space Grotesk carries body
/// text. Anton has a single weight, so its styles never set one.
abstract final class AppText {
  /// Space Grotesk ships as a single variable file, so weight is selected on
  /// the `wght` axis. [FontWeight] is set as well: if the variation axis is
  /// ever unavailable the renderer still picks a sensible synthetic weight
  /// instead of falling back to regular for everything.
  static TextStyle grotesk({
    required double size,
    double weight = 600,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight)],
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  static TextStyle anton({
    required double size,
    Color color = AppColors.text,
    double letterSpacing = 0.02,
    double? height,
  }) => TextStyle(
    fontFamily: 'Anton',
    fontSize: size,
    color: color,
    // The handoff expresses tracking in em; Flutter wants logical pixels.
    letterSpacing: size * letterSpacing,
    height: height,
  );

  /// Small all-caps label above a title ("SAT · JUL 18", "LOG").
  static TextStyle overline({
    double size = 11,
    Color color = AppColors.textMute,
    double tracking = 0.24,
  }) => grotesk(
    size: size,
    weight: 700,
    color: color,
    letterSpacing: size * tracking,
  );

  /// Anton section heading ("MEALS", "IN THIS MEAL").
  static TextStyle section({
    double size = 16,
    Color color = AppColors.textBright,
  }) => anton(size: size, color: color, letterSpacing: 0.03);

  /// A list row's primary line.
  static TextStyle rowTitle({Color color = AppColors.text}) =>
      grotesk(size: 14, weight: 700, color: color);

  /// A list row's secondary line.
  static TextStyle rowSubtitle({Color color = AppColors.textFaint2}) =>
      grotesk(size: 11, weight: 500, color: color);

  /// The trailing kcal figure on a list row.
  static TextStyle rowValue({double size = 20, Color color = AppColors.text}) =>
      anton(size: size, color: color);
}

abstract final class AppTheme {
  /// Horizontal screen padding. Every screen in the handoff uses 20px, except
  /// the search view which uses 18.
  static const screenPadding = 20.0;

  /// Gap between stacked list rows.
  static const rowGap = 2.0;

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.lime,
      onPrimary: AppColors.bg,
      secondary: AppColors.coral,
      onSecondary: AppColors.bg,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.coral,
      onError: AppColors.bg,
      outline: AppColors.strokeDashed,
      outlineVariant: AppColors.stroke,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      fontFamily: 'SpaceGrotesk',
      // Every surface in the design is square and flat.
      cardTheme: const CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.stroke,
        thickness: 1,
        space: 1,
      ),
      splashColor: AppColors.lime.withValues(alpha: 0.08),
      highlightColor: AppColors.lime.withValues(alpha: 0.04),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: AppText.grotesk(size: 13, weight: 600),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.lime,
        selectionColor: Color(0x33C6FF3A),
        selectionHandleColor: AppColors.lime,
      ),
    );
  }
}
