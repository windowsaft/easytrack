import 'package:easytrack/domain/tdee.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mifflin-St Jeor BMR', () {
    test('male reference case', () {
      // 80 kg, 180 cm, 30 y male:
      // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780.
      final bmr = basalMetabolicRate(
        sex: Sex.male,
        weightKg: 80,
        heightCm: 180,
        age: 30,
      );
      expect(bmr, closeTo(1780, 0.001));
    });

    test('female reference case', () {
      // 65 kg, 165 cm, 30 y female:
      // 10*65 + 6.25*165 - 5*30 - 161 = 650 + 1031.25 - 150 - 161 = 1370.25.
      final bmr = basalMetabolicRate(
        sex: Sex.female,
        weightKg: 65,
        heightCm: 165,
        age: 30,
      );
      expect(bmr, closeTo(1370.25, 0.001));
    });

    test('only the sex constant differs between male and female', () {
      double bmr(Sex sex) =>
          basalMetabolicRate(sex: sex, weightKg: 70, heightCm: 175, age: 40);
      expect(bmr(Sex.male) - bmr(Sex.female), closeTo(166, 0.001));
    });
  });

  group('TDEE and target', () {
    TdeeInputs inputs({
      Sex sex = Sex.male,
      ActivityLevel activity = ActivityLevel.moderate,
      WeightGoal goal = WeightGoal.maintain,
      double rate = 0,
    }) => TdeeInputs(
      sex: sex,
      age: 30,
      heightCm: 180,
      weightKg: 80,
      activity: activity,
      goal: goal,
      rateKgPerWeek: rate,
    );

    test('applies the activity multiplier to BMR', () {
      // BMR 1780 * 1.55 moderate = 2759.
      expect(totalDailyExpenditure(inputs()), closeTo(1780 * 1.55, 0.001));
    });

    test('maintenance target equals expenditure', () {
      final i = inputs();
      expect(
        recommendedCalorieTarget(i),
        closeTo(totalDailyExpenditure(i), 0.001),
      );
    });

    test('a loss goal subtracts the rate-derived offset', () {
      // 0.5 kg/week loss = 0.5*7700/7 = 550 kcal/day below maintenance.
      final i = inputs(goal: WeightGoal.lose, rate: 0.5);
      final maintenance = totalDailyExpenditure(i);
      expect(recommendedCalorieTarget(i), closeTo(maintenance - 550, 0.001));
    });

    test('a gain goal adds the offset', () {
      final i = inputs(goal: WeightGoal.gain, rate: 0.25);
      final maintenance = totalDailyExpenditure(i);
      expect(
        recommendedCalorieTarget(i),
        closeTo(maintenance + 0.25 * 7700 / 7, 0.001),
      );
    });

    test('never recommends below the 1200 kcal floor', () {
      // A tiny person with an absurd loss rate would compute well under 1200.
      final i = TdeeInputs(
        sex: Sex.female,
        age: 60,
        heightCm: 150,
        weightKg: 45,
        activity: ActivityLevel.sedentary,
        goal: WeightGoal.lose,
        rateKgPerWeek: 1.5,
      );
      expect(recommendedCalorieTarget(i), 1200);
    });
  });

  group('inputs completeness', () {
    test('rejects missing or absurd values', () {
      TdeeInputs withAge(int age) => TdeeInputs(
        sex: Sex.male,
        age: age,
        heightCm: 180,
        weightKg: 80,
        activity: ActivityLevel.moderate,
        goal: WeightGoal.maintain,
      );
      expect(withAge(0).isComplete, isFalse);
      expect(withAge(200).isComplete, isFalse);
      expect(withAge(30).isComplete, isTrue);
    });
  });

  group('wire mapping', () {
    test('activity level round-trips and defaults to moderate', () {
      for (final level in ActivityLevel.values) {
        expect(ActivityLevel.fromWire(level.wire), level);
      }
      expect(ActivityLevel.fromWire('nonsense'), ActivityLevel.moderate);
    });

    test('sex maps only known values', () {
      expect(Sex.fromWire('male'), Sex.male);
      expect(Sex.fromWire('female'), Sex.female);
      expect(Sex.fromWire(null), isNull);
      expect(Sex.fromWire('other'), isNull);
    });
  });
}
