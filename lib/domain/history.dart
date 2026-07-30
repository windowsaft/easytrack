import '../core/time/day_key.dart';

/// One day's rolled-up totals, for the Verlauf analytics.
///
/// [targetKcal] is the calorie target that was in force on [day] (targets are
/// history-preserving), so "eaten vs. target" is honest for any past day.
class DayHistory {
  const DayHistory({
    required this.day,
    required this.kcal,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    required this.waterMl,
    required this.activityKcal,
    required this.targetKcal,
    this.activityAddsToBudget = true,
  });

  final DayKey day;
  final double kcal;
  final double carbsG;
  final double proteinG;
  final double fatG;
  final int waterMl;
  final double activityKcal;
  final double targetKcal;

  /// Whether the activity bonus counts toward the day's allowance — the profile
  /// setting the diary uses for [budgetKcal]. Mirrors DaySummary so the Verlauf
  /// verdict matches the day dashboard.
  final bool activityAddsToBudget;

  /// Whether anything was eaten this day. Days with no food are excluded from
  /// averages so a not-yet-logged day does not read as "0 kcal eaten".
  bool get hasData => kcal > 0;

  /// The day's real calorie allowance: the base target plus any activity bonus,
  /// in step with the diary's DaySummary.budgetKcal.
  double get budgetKcal =>
      targetKcal + (activityAddsToBudget ? activityKcal : 0);

  /// Consumed minus the base target: negative under, positive over. This is the
  /// distance from the goal the deviation tile reports, deliberately *not*
  /// budget-adjusted.
  double get deviation => kcal - targetKcal;

  /// Over the day's real allowance — the budget, not just the base target — so a
  /// day eaten into an earned activity bonus does not read as "over".
  bool get isOverTarget => kcal > budgetKcal;

  /// On target for the adherence stat: within budget and not a big shortfall
  /// below the base goal. Consistent with [isOverTarget], unlike the old
  /// symmetric band which could count a day the chart painted red.
  bool get isOnTarget =>
      hasData &&
      kcal <= budgetKcal &&
      kcal >= targetKcal * (1 - HistorySummary.adherenceBand);
}

/// Summary statistics over a span of [DayHistory], for the Verlauf header tiles
/// and the macro-average split. Pure and list-driven so it is unit-testable.
class HistorySummary {
  const HistorySummary({
    required this.periodDays,
    required this.daysLogged,
    required this.adherentDays,
    required this.avgKcal,
    required this.avgDeviation,
    required this.avgCarbsG,
    required this.avgProteinG,
    required this.avgFatG,
    required this.avgWaterMl,
    required this.avgActivityKcal,
  });

  /// How far below the base goal a logged day may fall and still count as "on
  /// target". The upper bound is the day's budget (base + activity), not a
  /// percentage — see [DayHistory.isOnTarget].
  static const adherenceBand = 0.15;

  final int periodDays;
  final int daysLogged;
  final int adherentDays;
  final double avgKcal;
  final double avgDeviation;
  final double avgCarbsG;
  final double avgProteinG;
  final double avgFatG;
  final double avgWaterMl;
  final double avgActivityKcal;

  /// Fraction of the average plate that is carbs / protein / fat by grams. Zero
  /// across the board when nothing has been logged.
  ({double carbs, double protein, double fat}) get macroSplit {
    final total = avgCarbsG + avgProteinG + avgFatG;
    if (total <= 0) return (carbs: 0, protein: 0, fat: 0);
    return (
      carbs: avgCarbsG / total,
      protein: avgProteinG / total,
      fat: avgFatG / total,
    );
  }

  factory HistorySummary.of(List<DayHistory> days) {
    final logged = days.where((d) => d.hasData).toList();
    if (logged.isEmpty) {
      return HistorySummary(
        periodDays: days.length,
        daysLogged: 0,
        adherentDays: 0,
        avgKcal: 0,
        avgDeviation: 0,
        avgCarbsG: 0,
        avgProteinG: 0,
        avgFatG: 0,
        avgWaterMl: 0,
        avgActivityKcal: 0,
      );
    }

    double mean(double Function(DayHistory) f) =>
        logged.map(f).reduce((a, b) => a + b) / logged.length;

    final adherent = logged.where((d) => d.isOnTarget).length;

    return HistorySummary(
      periodDays: days.length,
      daysLogged: logged.length,
      adherentDays: adherent,
      avgKcal: mean((d) => d.kcal),
      avgDeviation: mean((d) => d.deviation),
      avgCarbsG: mean((d) => d.carbsG),
      avgProteinG: mean((d) => d.proteinG),
      avgFatG: mean((d) => d.fatG),
      avgWaterMl: mean((d) => d.waterMl.toDouble()),
      avgActivityKcal: mean((d) => d.activityKcal),
    );
  }
}
