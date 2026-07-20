import '../core/nutrition/food_ref.dart';
import '../core/nutrition/nutrients.dart';

/// One ingredient of a recipe, resolved to a concrete weight and its nutrient
/// contribution.
///
/// [nutrients] are absolute for [amountG] — already multiplied out from the
/// source food's per-100 g values and snapshotted at the moment the ingredient
/// was added, exactly as a diary entry snapshots what was logged. A later
/// correction to the source food must not silently rewrite a saved recipe.
class RecipeComponent {
  const RecipeComponent({
    required this.ref,
    required this.name,
    required this.amountG,
    required this.nutrients,
  });

  final FoodRef ref;
  final String name;
  final double amountG;

  /// Absolute nutrients for [amountG] of this ingredient.
  final Nutrients nutrients;

  /// The per-100 g values this ingredient was logged at, recovered from its
  /// snapshot. Lets the editor reopen a weight picker without re-reading the
  /// source food (which may since have changed, or live in a replaced pack).
  Nutrients get per100g =>
      amountG <= 0 ? Nutrients.zero : nutrients.scaled(100 / amountG);

  RecipeComponent withAmount(double newAmountG) => RecipeComponent(
    ref: ref,
    name: name,
    amountG: newAmountG,
    nutrients: per100g.forGrams(newAmountG),
  );
}

/// Portion scaling for a recipe.
///
/// Ingredients sum to a raw batch. Cooking drives off water, so the finished
/// dish can weigh less than the raw sum without losing any calories: when a
/// [yieldWeightG] cooked weight is recorded, portions scale against it instead
/// of the raw batch weight, which is the difference between an honest and an
/// inflated calorie count. A 1,400 g raw batch cooked down to 1,100 g carries
/// the same energy in denser grams, and a 450 g plate off it must reflect that.
class RecipeScaling {
  RecipeScaling._({
    required this.batchNutrients,
    required this.batchWeightG,
    required double? cookedWeightG,
  }) : yieldWeightG = (cookedWeightG != null && cookedWeightG > 0)
           ? cookedWeightG
           : batchWeightG;

  /// Sums the components into a batch, optionally overriding its yield weight.
  factory RecipeScaling.of(
    Iterable<RecipeComponent> components, {
    double? cookedWeightG,
  }) {
    var total = Nutrients.zero;
    var batch = 0.0;
    for (final c in components) {
      total = total + c.nutrients;
      batch += c.amountG;
    }
    return RecipeScaling._(
      batchNutrients: total,
      batchWeightG: batch,
      cookedWeightG: cookedWeightG,
    );
  }

  /// Summed nutrients of the whole batch. Independent of the yield weight —
  /// water leaving the pot changes weight, not energy.
  final Nutrients batchNutrients;

  /// The raw weight: the sum of the ingredient weights.
  final double batchWeightG;

  /// The weight a portion is measured against — the cooked weight when one was
  /// recorded, otherwise the raw batch weight.
  final double yieldWeightG;

  /// True when there is nothing to scale, so [per100g] and [forPortion] would
  /// otherwise divide by zero.
  bool get isEmpty => batchWeightG <= 0 || yieldWeightG <= 0;

  /// Nutrients per 100 g of the finished dish. [Nutrients.zero] for an empty
  /// recipe, so callers never have to guard the division themselves.
  Nutrients get per100g =>
      isEmpty ? Nutrients.zero : batchNutrients.scaled(100 / yieldWeightG);

  /// Nutrients for a served portion of [grams] of the finished dish.
  Nutrients forPortion(double grams) =>
      isEmpty ? Nutrients.zero : batchNutrients.scaled(grams / yieldWeightG);
}
