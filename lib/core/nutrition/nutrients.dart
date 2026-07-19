import 'dart:math' as math;

/// The nutrients tracked per food, expressed **per 100 g**.
///
/// Every provider normalizes to this shape, which is what lets BLS, Open Food
/// Facts and user-created foods flow through the same code paths.
///
/// Nullable fields mean "not known", which is distinct from `0`. BLS encodes
/// this distinction explicitly (see `docs/bls-format.md`) and losing it would
/// display an unmeasured food as fat-free.
class Nutrients {
  const Nutrients({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.sugarG,
    this.fiberG,
    this.satFatG,
    this.saltG,
  });

  static const zero = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double? sugarG;
  final double? fiberG;
  final double? satFatG;
  final double? saltG;

  /// Scales per-100g values to an absolute amount in grams.
  Nutrients forGrams(double grams) => scaled(grams / 100.0);

  Nutrients scaled(double factor) => Nutrients(
    kcal: kcal * factor,
    proteinG: proteinG * factor,
    carbsG: carbsG * factor,
    fatG: fatG * factor,
    sugarG: _mul(sugarG, factor),
    fiberG: _mul(fiberG, factor),
    satFatG: _mul(satFatG, factor),
    saltG: _mul(saltG, factor),
  );

  /// Adds two absolute nutrient totals.
  ///
  /// An unknown optional value is treated as absent rather than zero: adding a
  /// food with unknown fiber to one with 3 g must not claim the total is 3 g.
  /// Only when both sides are unknown does the result stay unknown.
  Nutrients operator +(Nutrients other) => Nutrients(
    kcal: kcal + other.kcal,
    proteinG: proteinG + other.proteinG,
    carbsG: carbsG + other.carbsG,
    fatG: fatG + other.fatG,
    sugarG: _add(sugarG, other.sugarG),
    fiberG: _add(fiberG, other.fiberG),
    satFatG: _add(satFatG, other.satFatG),
    saltG: _add(saltG, other.saltG),
  );

  /// Energy recomputed from macros using Atwater factors, for sanity checks.
  double get kcalFromMacros => proteinG * 4 + carbsG * 4 + fatG * 9;

  /// Whether the stated energy is plausible given the macros.
  ///
  /// Real data has rounding, fiber and polyols, and alcohol is not counted in
  /// the four macros at all, so the tolerance is deliberately loose. This is a
  /// smell test for bad imports, not a validator.
  bool get energyLooksPlausible {
    if (kcal <= 0) return kcalFromMacros < 5;
    final diff = (kcal - kcalFromMacros).abs();
    return diff <= math.max(30, kcal * 0.30);
  }

  static double? _mul(double? v, double f) => v == null ? null : v * f;

  static double? _add(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a + b;
  }

  @override
  String toString() =>
      'Nutrients(${kcal.toStringAsFixed(0)} kcal, P${proteinG.toStringAsFixed(1)} '
      'C${carbsG.toStringAsFixed(1)} F${fatG.toStringAsFixed(1)})';
}
