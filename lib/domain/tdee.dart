import 'nutrients_targets.dart';

/// Biological sex, as it enters the Mifflin-St Jeor equation.
///
/// This is strictly the metabolic constant the formula needs, not an identity
/// field — a user who would rather not answer sets a manual calorie target
/// instead, which is why the profile allows that path.
enum Sex {
  male('male', 'Männlich'),
  female('female', 'Weiblich');

  const Sex(this.wire, this.label);

  final String wire;
  final String label;

  static Sex? fromWire(String? value) => switch (value) {
    'male' => Sex.male,
    'female' => Sex.female,
    _ => null,
  };
}

/// How much daily movement to assume on top of the resting rate.
///
/// These are the standard Mifflin activity multipliers. The app also logs
/// exercise explicitly and adds it to the budget, so a user who logs workouts
/// should pick a *lower* band here than their gut says — otherwise the same
/// activity is counted twice. The labels hint at that.
enum ActivityLevel {
  sedentary('sedentary', 'Kaum Bewegung', 1.2, 'Bürojob, wenig Sport'),
  light('light', 'Leicht aktiv', 1.375, '1–3× Sport pro Woche'),
  moderate('moderate', 'Mäßig aktiv', 1.55, '3–5× Sport pro Woche'),
  active('active', 'Sehr aktiv', 1.725, '6–7× Sport pro Woche'),
  veryActive('very_active', 'Extrem aktiv', 1.9, 'Körperlicher Job + Sport');

  const ActivityLevel(this.wire, this.label, this.factor, this.hint);

  final String wire;
  final String label;
  final double factor;
  final String hint;

  static ActivityLevel fromWire(String? value) => values.firstWhere(
    (e) => e.wire == value,
    orElse: () => ActivityLevel.moderate,
  );
}

/// The direction of the calorie adjustment relative to maintenance.
enum WeightGoal {
  lose('lose', 'Abnehmen', -1),
  maintain('maintain', 'Halten', 0),
  gain('gain', 'Zunehmen', 1);

  const WeightGoal(this.wire, this.label, this.sign);

  final String wire;
  final String label;

  /// −1, 0 or +1: multiplies the rate-derived daily calorie change.
  final int sign;

  static WeightGoal fromWire(String? value) => values.firstWhere(
    (e) => e.wire == value,
    orElse: () => WeightGoal.maintain,
  );
}

/// The inputs the calorie target is derived from.
class TdeeInputs {
  const TdeeInputs({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.goal,
    this.rateKgPerWeek = 0,
  });

  final Sex sex;
  final int age;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activity;
  final WeightGoal goal;

  /// Intended weekly change, always a positive magnitude; [WeightGoal] carries
  /// the direction. Zero for maintenance.
  final double rateKgPerWeek;

  /// Whether every field needed for a computation is present and sane.
  bool get isComplete => age > 0 && age < 130 && heightCm > 0 && weightKg > 0;
}

/// Mifflin-St Jeor basal metabolic rate: calories burned at complete rest.
///
/// Chosen over Harris-Benedict because it tracks measured resting expenditure
/// more closely in modern populations. Body-fat-aware formulas (Katch-McArdle)
/// are more accurate still but need a body-fat percentage the app does not ask
/// for, so this is the honest best given the inputs.
double basalMetabolicRate({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  // The only term that differs by sex.
  return base + (sex == Sex.male ? 5 : -161);
}

/// Calories burned on an average day at the given activity level, before any
/// deliberately logged exercise.
double totalDailyExpenditure(TdeeInputs inputs) =>
    basalMetabolicRate(
      sex: inputs.sex,
      weightKg: inputs.weightKg,
      heightCm: inputs.heightCm,
      age: inputs.age,
    ) *
    inputs.activity.factor;

/// One kilogram of body fat is treated as 7,700 kcal — the standard rule of
/// thumb for translating a weekly weight-change goal into a daily calorie
/// offset.
const _kcalPerKg = 7700.0;

/// The recommended daily calorie target: maintenance shifted by the goal.
///
/// A loss target is floored so the equation can never recommend a dangerously
/// low intake for a small person with an aggressive rate — the UI should also
/// warn, but the number itself must not go there.
double recommendedCalorieTarget(TdeeInputs inputs) {
  final maintenance = totalDailyExpenditure(inputs);
  final dailyOffset = inputs.goal.sign * inputs.rateKgPerWeek * _kcalPerKg / 7;
  final target = maintenance + dailyOffset;

  // A hard floor near the resting rate: eating below BMR for long is the thing
  // this floor exists to refuse to suggest.
  const floor = 1200.0;
  return target < floor ? floor : target;
}

/// A default macronutrient split for a calorie target, when the user has not
/// set their own. Uses a balanced 40 / 30 / 30 of carbs / protein / fat by
/// energy — the same split the settings screen shows as its example.
MacroTargets defaultMacrosFor(double kcal) => MacroTargets.fromSplit(
  kcal: kcal,
  carbFraction: 0.40,
  proteinFraction: 0.30,
  fatFraction: 0.30,
);
