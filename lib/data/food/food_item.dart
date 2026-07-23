import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/measure_unit.dart';
import '../../core/nutrition/nutrients.dart';

/// A portion the user can pick instead of typing a raw amount.
///
/// A serving is a *named unit* plus the amount of one of it — "Portion",
/// "Cookie", "Scheibe", "Ganze Menge". The portion sheet multiplies it by a
/// count (1×, 2×, 3× …), so the label describes a single unit and never bakes in
/// the count: "Cookie (25 g)", not "1 Cookie (25 g)". [measure] decides whether
/// the amount reads in g or ml, so a drink's serving shows "Portion (100 ml)".
class ServingOption {
  const ServingOption({
    required this.unit,
    required this.grams,
    this.measure = MeasureUnit.grams,
  });

  /// The noun for one serving. The raw fallback uses the measure suffix ("g"/"ml").
  final String unit;

  /// Amount of a single [unit] in the food's [measure]. The raw fallback carries
  /// 1, since its amount field is the raw measure directly, not a count of units.
  final double grams;

  /// Whether this serving is counted in grams or millilitres.
  final MeasureUnit measure;

  /// The raw fallback for [measure]: the amount typed is g/ml, not a unit count.
  factory ServingOption.raw(MeasureUnit measure) =>
      ServingOption(unit: measure.suffix, grams: 1, measure: measure);

  /// Whether this is the raw option (amount field is the measure, not a count).
  bool get isRaw => unit == measure.suffix;

  /// One unit and its amount, without a count: "Portion (30 g)", "Cola (330 ml)".
  /// Callers store this on a logged entry and pair it with the picked count.
  String get label => '$unit (${_fmt(grams)} ${measure.suffix})';

  /// A label describing [defaultGrams] for a search row, where there is no count
  /// field: "100 ml" in raw mode, otherwise the unit label.
  String get portionLabel =>
      isRaw ? '${_fmt(defaultGrams)} ${measure.suffix}' : label;

  /// The amount the field starts at: one unit, or 100 in raw mode.
  double get defaultAmount => isRaw ? 100 : 1;

  /// The base amount logged for [defaultAmount]: 100 (g/ml) in raw mode, one
  /// unit otherwise. Used by search rows and quick logging that skip the sheet.
  double get defaultGrams => isRaw ? 100 : grams;

  static String _fmt(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  // Value equality, because the portion sheet rebuilds its choices on every
  // frame — the raw fallback is a fresh instance each call — and decides which
  // chip is highlighted with `option == selected`. Identity would leave the
  // just-picked "Gramm"/"Milliliter" chip looking unselected.
  @override
  bool operator ==(Object other) =>
      other is ServingOption &&
      other.unit == unit &&
      other.grams == grams &&
      other.measure == measure;

  @override
  int get hashCode => Object.hash(unit, grams, measure);
}

/// A food from any source, normalized to one shape.
///
/// Everything downstream — search results, the diary, recipes — works with this
/// rather than with source-specific rows, which is what lets a new provider be
/// added without touching the rest of the app.
class FoodItem {
  const FoodItem({
    required this.ref,
    required this.name,
    required this.nutrients,
    this.brand,
    this.foodGroup,
    this.servings = const [],
    this.barcode,
    this.measure = MeasureUnit.grams,
  });

  final FoodRef ref;
  final String name;
  final String? brand;
  final String? foodGroup;

  /// Always per 100 g (or per 100 ml for a liquid — 1 ml ≈ 1 g).
  final Nutrients nutrients;

  /// Portion shortcuts. May be empty, in which case the UI offers the raw amount.
  final List<ServingOption> servings;

  final String? barcode;

  /// Whether this food is measured by mass (g) or volume (ml). Drinks are ml.
  final MeasureUnit measure;

  /// Source label for the attribution chip. Licences require this to be shown.
  String get sourceLabel => ref.source.displayLabel;

  /// Whether this food logs and displays in millilitres.
  bool get isLiquid => measure.isLiquid;

  /// "Brand — Name" when a brand is known, otherwise just the name.
  String get displayTitle =>
      brand == null || brand!.isEmpty ? name : '$name ($brand)';

  /// Serving options plus a raw-amount fallback, so the picker is never empty.
  List<ServingOption> get servingChoices => servings.isEmpty
      ? [ServingOption.raw(measure)]
      : [...servings, ServingOption.raw(measure)];

  /// The portion a search result is shown and quick-added with.
  ///
  /// BLS entries are per-100 g generics with no natural serving, so this falls
  /// back to the raw amount (defaulting to 100 g/ml) rather than inventing a
  /// "1 bowl" the data does not support.
  ServingOption get defaultServing =>
      servings.isEmpty ? ServingOption.raw(measure) : servings.first;

  /// Base amount logged when the food is added at its default serving without
  /// opening the portion sheet (search rows, quick add, the tray).
  double get defaultGrams => defaultServing.defaultGrams;
}

/// A [FoodItem] with the score its provider assigned.
///
/// Scores are only comparable within one provider; the orchestrator normalizes
/// them before merging.
class FoodSearchResult {
  const FoodSearchResult({
    required this.item,
    required this.rawScore,
    this.exactMatch = false,
    this.prefixMatch = false,
  });

  final FoodItem item;

  /// Provider-local relevance. For FTS sources this is `-bm25`, so higher is
  /// better and the sign convention is uniform across providers.
  final double rawScore;

  final bool exactMatch;
  final bool prefixMatch;
}
