/// A macronutrient target in grams, derived from a calorie total and a split.
///
/// Grams are what the diary compares against, but the split is expressed in
/// energy fractions because that is how nutrition guidance is stated ("30 % of
/// calories from protein"). Converting once, here, keeps that conversion out of
/// the UI.
class MacroTargets {
  const MacroTargets({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Splits [kcal] by energy fraction into grams, using Atwater factors
  /// (4 kcal/g for protein and carbohydrate, 9 for fat).
  ///
  /// The fractions are not required to sum to exactly 1; each is applied to the
  /// calorie total independently, so a caller passing 0.4/0.3/0.3 gets a clean
  /// result and a caller passing something lopsided still gets a sensible one.
  factory MacroTargets.fromSplit({
    required double kcal,
    required double carbFraction,
    required double proteinFraction,
    required double fatFraction,
  }) => MacroTargets(
    carbsG: kcal * carbFraction / 4,
    proteinG: kcal * proteinFraction / 4,
    fatG: kcal * fatFraction / 9,
  );
}
