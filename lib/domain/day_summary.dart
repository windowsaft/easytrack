import '../core/nutrition/food_ref.dart';
import '../core/nutrition/nutrients.dart';
import '../core/time/day_key.dart';
import '../data/db/user_database.dart';

/// One day's logged entries, grouped by meal, with totals.
class DaySummary {
  const DaySummary({
    required this.day,
    required this.entriesByMeal,
    required this.waterMl,
    required this.activityKcalRaw,
    required this.activityKcalAdjusted,
    required this.target,
  });

  final DayKey day;
  final Map<MealType, List<DiaryEntry>> entriesByMeal;
  final int waterMl;

  /// Burned calories as entered, before the safety factor.
  final double activityKcalRaw;

  /// Burned calories after each entry's safety factor — what counts.
  final double activityKcalAdjusted;

  final DayTarget target;

  List<DiaryEntry> entriesFor(MealType meal) => entriesByMeal[meal] ?? const [];

  /// Total nutrients eaten, summed from the per-entry snapshots.
  Nutrients get consumed {
    var total = Nutrients.zero;
    for (final entries in entriesByMeal.values) {
      for (final entry in entries) {
        total = total + _entryNutrients(entry);
      }
    }
    return total;
  }

  Nutrients nutrientsFor(MealType meal) {
    var total = Nutrients.zero;
    for (final entry in entriesFor(meal)) {
      total = total + _entryNutrients(entry);
    }
    return total;
  }

  /// The day's calorie allowance, including any activity bonus.
  double get budgetKcal =>
      target.kcal + (target.activityAddsToBudget ? activityKcalAdjusted : 0);

  /// Calories still available. Negative once the budget is exceeded.
  double get remainingKcal => budgetKcal - consumed.kcal;

  bool get isOverBudget => remainingKcal < 0;

  int get totalEntryCount =>
      entriesByMeal.values.fold(0, (sum, list) => sum + list.length);

  static Nutrients _entryNutrients(DiaryEntry entry) => Nutrients(
    // Entries store absolute values, already multiplied out at logging time.
    kcal: entry.kcal,
    proteinG: entry.proteinG,
    carbsG: entry.carbsG,
    fatG: entry.fatG,
    sugarG: entry.sugarG,
    fiberG: entry.fiberG,
    satFatG: entry.satFatG,
    saltG: entry.saltG,
  );
}

/// The target in force on a given day.
class DayTarget {
  const DayTarget({
    required this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.waterMl = 2000,
    this.activityAddsToBudget = true,
  });

  /// Used until the user sets up a profile. Deliberately a round, obviously
  /// provisional number rather than a computed one.
  static const fallback = DayTarget(kcal: 2000);

  final double kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final int waterMl;
  final bool activityAddsToBudget;
}
