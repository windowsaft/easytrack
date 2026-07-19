import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nutrients', () {
    const oats = Nutrients(
      kcal: 348,
      proteinG: 13.22,
      carbsG: 58.7,
      fatG: 7.0,
      fiberG: 9.5,
    );

    test('scales per-100g values to an amount in grams', () {
      final portion = oats.forGrams(50);
      expect(portion.kcal, closeTo(174, 0.01));
      expect(portion.proteinG, closeTo(6.61, 0.01));
      expect(portion.fiberG, closeTo(4.75, 0.01));
    });

    test('scaling by zero grams yields zero, not the per-100g values', () {
      expect(oats.forGrams(0).kcal, 0);
    });

    test('scaling above 100 g extrapolates', () {
      expect(oats.forGrams(250).kcal, closeTo(870, 0.01));
    });

    test('addition sums the required macros', () {
      final total = oats.forGrams(100) + oats.forGrams(100);
      expect(total.kcal, closeTo(696, 0.01));
      expect(total.proteinG, closeTo(26.44, 0.01));
    });

    test('unknown optional values do not masquerade as zero when added', () {
      const withFiber = Nutrients(
        kcal: 100,
        proteinG: 1,
        carbsG: 10,
        fatG: 1,
        fiberG: 3,
      );
      const withoutFiber = Nutrients(
        kcal: 100,
        proteinG: 1,
        carbsG: 10,
        fatG: 1,
      );

      // Known + unknown keeps the known value rather than inventing a total.
      expect((withFiber + withoutFiber).fiberG, 3);
      expect((withoutFiber + withFiber).fiberG, 3);
      // Unknown + unknown stays unknown.
      expect((withoutFiber + withoutFiber).fiberG, isNull);
      // Known + known adds.
      expect((withFiber + withFiber).fiberG, 6);
    });

    test('scaling preserves unknown as unknown', () {
      const noFiber = Nutrients(kcal: 100, proteinG: 1, carbsG: 10, fatG: 1);
      expect(noFiber.forGrams(50).fiberG, isNull);
    });

    test('computes energy from macros with Atwater factors', () {
      const sample = Nutrients(kcal: 0, proteinG: 10, carbsG: 20, fatG: 5);
      expect(sample.kcalFromMacros, closeTo(10 * 4 + 20 * 4 + 5 * 9, 0.001));
    });

    test('flags implausible energy but tolerates real-world rounding', () {
      expect(oats.energyLooksPlausible, isTrue);
      // Claiming 20 kcal for 50 g of fat is not survivable rounding.
      const bogus = Nutrients(kcal: 20, proteinG: 0, carbsG: 0, fatG: 50);
      expect(bogus.energyLooksPlausible, isFalse);
    });

    test('zero constant is a true zero', () {
      expect(Nutrients.zero.kcal, 0);
      expect(Nutrients.zero.energyLooksPlausible, isTrue);
    });
  });
}
