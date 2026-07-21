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
  });

  final DayKey day;
  final double kcal;
  final double carbsG;
  final double proteinG;
  final double fatG;
  final int waterMl;
  final double activityKcal;
  final double targetKcal;

  /// Whether anything was eaten this day. Days with no food are excluded from
  /// averages so a not-yet-logged day does not read as "0 kcal eaten".
  bool get hasData => kcal > 0;

  /// Consumed minus target: negative under, positive over.
  double get deviation => kcal - targetKcal;

  bool get isOverTarget => kcal > targetKcal;
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

  /// A logged day counts as "on target" when its intake lands within this band
  /// of the target — neither a big overshoot nor a big shortfall.
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

    final adherent = logged
        .where((d) => d.deviation.abs() <= d.targetKcal * adherenceBand)
        .length;

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
