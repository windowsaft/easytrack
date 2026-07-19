import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';

/// A portion the user can pick instead of typing grams.
class ServingOption {
  const ServingOption({required this.label, required this.grams});

  /// Shown as-is: "1 Scheibe", "1 Packung (250 g)".
  final String label;
  final double grams;

  static const per100g = ServingOption(label: '100 g', grams: 100);
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
  });

  final FoodRef ref;
  final String name;
  final String? brand;
  final String? foodGroup;

  /// Always per 100 g.
  final Nutrients nutrients;

  /// Portion shortcuts. May be empty, in which case the UI offers grams.
  final List<ServingOption> servings;

  final String? barcode;

  /// Source label for the attribution chip. Licences require this to be shown.
  String get sourceLabel => ref.source.displayLabel;

  /// "Brand — Name" when a brand is known, otherwise just the name.
  String get displayTitle =>
      brand == null || brand!.isEmpty ? name : '$name ($brand)';

  /// Serving options plus a 100 g fallback, so the picker is never empty.
  List<ServingOption> get servingChoices => servings.isEmpty
      ? const [ServingOption.per100g]
      : [...servings, ServingOption.per100g];
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
