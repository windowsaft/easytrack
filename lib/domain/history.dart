import 'dart:math' as math;

import '../core/time/day_key.dart';
import '../core/time/week_start.dart';

/// The unit the Verlauf tab pages by.
enum HistoryUnit {
  week(7),
  month(30);

  const HistoryUnit(this.rollingDays);

  /// How many days this unit's rolling window covers.
  final int rollingDays;
}

/// Which stretch of days the Verlauf tab is showing, and how it moves.
///
/// [offset] 0 is the rolling window ending today — the default the tab has
/// always had. Below that the range leaves the rolling frame and walks whole
/// calendar units instead, because "the week before" only means anything on a
/// calendar boundary. [custom] is a hand-picked span and overrides both.
///
/// Today is injected rather than read from the clock so the stepping and
/// clamping rules can be tested without freezing time.
class HistoryRange {
  const HistoryRange(this.unit, {this.offset = 0, this.custom});

  final HistoryUnit unit;
  final int offset;
  final ({DayKey from, DayKey to})? custom;

  /// Whether this is the untouched default: the window ending today.
  bool get isRolling => custom == null && offset == 0;

  /// The inclusive range of days to load.
  ({DayKey from, DayKey to}) days(DayKey today, WeekStart weekStart) {
    final custom = this.custom;
    if (custom != null) return custom;
    if (offset == 0) {
      return (from: today.addDays(-(unit.rollingDays - 1)), to: today);
    }
    return switch (unit) {
      HistoryUnit.week => _calendarWeek(today, weekStart),
      HistoryUnit.month => _calendarMonth(today),
    };
  }

  /// Forward is blocked once the range has caught up with today — there is no
  /// history ahead of it to show.
  bool canStepForward(DayKey today) {
    final custom = this.custom;
    return custom == null ? offset < 0 : custom.to.daysUntil(today) > 0;
  }

  /// One unit back (-1) or forward (+1). A custom span moves by its own length,
  /// clamped so it never runs past today.
  HistoryRange step(int direction, DayKey today) {
    final custom = this.custom;
    if (custom == null) return HistoryRange(unit, offset: offset + direction);

    final span = custom.from.daysUntil(custom.to) + 1;
    final shift = direction > 0
        ? math.min(span, custom.to.daysUntil(today))
        : -span;
    return HistoryRange(
      unit,
      custom: (from: custom.from.addDays(shift), to: custom.to.addDays(shift)),
    );
  }

  /// Switching unit returns to that unit's rolling window: carrying a "three
  /// weeks back" offset over to months would land somewhere unasked for.
  HistoryRange withUnit(HistoryUnit unit) => HistoryRange(unit);

  HistoryRange withCustom(DayKey from, DayKey to) =>
      HistoryRange(unit, custom: (from: from, to: to));

  ({DayKey from, DayKey to}) _calendarWeek(DayKey today, WeekStart weekStart) {
    final from = weekStart.startOfWeek(today).addDays(offset * 7);
    return (from: from, to: from.addDays(6));
  }

  ({DayKey from, DayKey to}) _calendarMonth(DayKey today) {
    final first = DateTime(today.year, today.month + offset, 1);
    // Day 0 of the following month is the last day of this one, so this lands
    // on 28/29/30/31 without a table.
    final last = DateTime(first.year, first.month + 1, 0);
    return (from: DayKey.fromDate(first), to: DayKey.fromDate(last));
  }
}

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
