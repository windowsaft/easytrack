import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

/// One ingredient, with absolute nutrients for its weight — the shape the
/// repository stores after multiplying a per-100 g food out.
RecipeComponent component(
  String name,
  double amountG, {
  required double kcal,
  double protein = 0,
  double carbs = 0,
  double fat = 0,
}) => RecipeComponent(
  ref: FoodRef(FoodSourceType.bls, name),
  name: name,
  amountG: amountG,
  nutrients: Nutrients(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat),
);

void main() {
  // The worked example from the plan's recipe section.
  final chili = [
    component('Hackfleisch', 500, kcal: 1050, protein: 100, fat: 75),
    component('Kidneybohnen', 400, kcal: 380, protein: 26, carbs: 60, fat: 2),
    component(
      'Tomaten passiert',
      500,
      kcal: 175,
      protein: 8,
      carbs: 35,
      fat: 1,
    ),
  ];

  group('RecipeScaling', () {
    test('sums ingredients into a batch', () {
      final scaling = RecipeScaling.of(chili);
      expect(scaling.batchWeightG, 1400);
      expect(scaling.batchNutrients.kcal, closeTo(1605, 0.01));
      expect(scaling.batchNutrients.carbsG, closeTo(95, 0.01));
      expect(scaling.batchNutrients.fatG, closeTo(78, 0.01));
      expect(scaling.batchNutrients.proteinG, closeTo(134, 0.01));
    });

    test('without a cooked weight the yield is the raw batch weight', () {
      final scaling = RecipeScaling.of(chili);
      expect(scaling.yieldWeightG, 1400);
      // 1605 kcal / 1400 g * 100.
      expect(scaling.per100g.kcal, closeTo(114.64, 0.01));
    });

    test('a portion scales by weight against the batch', () {
      final scaling = RecipeScaling.of(chili);
      // 1605 * 450 / 1400.
      expect(scaling.forPortion(450).kcal, closeTo(515.89, 0.01));
      expect(scaling.forPortion(450).proteinG, closeTo(43.07, 0.01));
    });

    test('a cooked weight makes the same portion denser in calories', () {
      // The pot cooked down from 1400 g to 1100 g; the energy did not change,
      // so every gram — and every plate — carries more of it.
      final scaling = RecipeScaling.of(chili, cookedWeightG: 1100);
      expect(scaling.yieldWeightG, 1100);
      expect(scaling.per100g.kcal, closeTo(145.91, 0.01));
      // 1605 * 450 / 1100.
      expect(scaling.forPortion(450).kcal, closeTo(656.59, 0.01));
    });

    test('a zero or negative cooked weight falls back to the batch', () {
      expect(RecipeScaling.of(chili, cookedWeightG: 0).yieldWeightG, 1400);
      expect(RecipeScaling.of(chili, cookedWeightG: -5).yieldWeightG, 1400);
    });

    test('an empty recipe scales to zero without dividing by zero', () {
      final scaling = RecipeScaling.of(const []);
      expect(scaling.isEmpty, isTrue);
      expect(scaling.per100g.kcal, 0);
      expect(scaling.forPortion(300).kcal, 0);
    });
  });

  group('RecipeComponent', () {
    test('recovers per-100 g values from its snapshot', () {
      final c = component(
        'Hackfleisch',
        500,
        kcal: 1050,
        protein: 100,
        fat: 75,
      );
      expect(c.per100g.kcal, closeTo(210, 0.01));
      expect(c.per100g.proteinG, closeTo(20, 0.01));
      expect(c.per100g.fatG, closeTo(15, 0.01));
    });

    test('rescaling the weight rescales the snapshot from per-100 g', () {
      final c = component(
        'Hackfleisch',
        500,
        kcal: 1050,
        protein: 100,
        fat: 75,
      );
      final half = c.withAmount(250);
      expect(half.amountG, 250);
      expect(half.nutrients.kcal, closeTo(525, 0.01));
      expect(half.nutrients.proteinG, closeTo(50, 0.01));
    });
  });
}
