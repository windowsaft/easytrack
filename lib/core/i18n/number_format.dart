import 'package:intl/intl.dart';

/// Locale-aware number formatting.
///
/// The active locale is pinned globally by `LocaleController` via
/// `Intl.defaultLocale`, so these helpers pick up the app language and emit the
/// right decimal and grouping separators — "72.4" / "1,250" in English,
/// "72,4" / "1.250" in German — without threading a locale through call sites.
///
/// All three build on `NumberFormat.decimalPattern()`, which resolves to the
/// current locale when no argument is given.

/// A whole number with grouping separators: 2100 -> "2,100" / "2.100".
/// The value is rounded to the nearest integer first.
String formatInt(num value) =>
    NumberFormat.decimalPattern().format(value.round());

/// Exactly [decimals] fraction digits: `formatFixed(0.85, 2)` -> "0.85" / "0,85".
/// Use when the count of decimals is meaningful and trailing zeros should stay.
String formatFixed(num value, int decimals) =>
    (NumberFormat.decimalPattern()
          ..minimumFractionDigits = decimals
          ..maximumFractionDigits = decimals)
        .format(value);

/// Up to [maxDecimals] fraction digits, trailing zeros trimmed:
/// `formatDecimal(72)` -> "72", `formatDecimal(72.4)` -> "72,4".
String formatDecimal(num value, {int maxDecimals = 1}) =>
    (NumberFormat.decimalPattern()..maximumFractionDigits = maxDecimals)
        .format(value);
