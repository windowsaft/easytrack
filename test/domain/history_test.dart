import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/core/time/week_start.dart';
import 'package:easytrack/domain/history.dart';
import 'package:flutter_test/flutter_test.dart';

DayHistory day(
  int d, {
  double kcal = 0,
  double carbs = 0,
  double protein = 0,
  double fat = 0,
  int water = 0,
  double activity = 0,
  double target = 2000,
}) => DayHistory(
  day: DayKey(d),
  kcal: kcal,
  carbsG: carbs,
  proteinG: protein,
  fatG: fat,
  waterMl: water,
  activityKcal: activity,
  targetKcal: target,
);

void main() {
  group('DayHistory', () {
    test('hasData tracks whether anything was eaten', () {
      expect(day(20260701).hasData, isFalse);
      expect(day(20260701, kcal: 10).hasData, isTrue);
    });

    test('deviation is consumed minus the base target', () {
      expect(day(20260701, kcal: 2400, target: 2000).deviation, 400);
      expect(day(20260701, kcal: 1800, target: 2000).deviation, -200);
    });

    test('over-target is measured against the activity-extended budget', () {
      // Above the base target but within base + burned → not over.
      final within = day(20260701, kcal: 2300, target: 2000, activity: 400);
      expect(within.budgetKcal, 2400);
      expect(within.isOverTarget, isFalse);
      // Above the budget → over.
      final over = day(20260701, kcal: 2500, target: 2000, activity: 400);
      expect(over.isOverTarget, isTrue);
    });

    test('a day within its budget counts as on target', () {
      expect(
        day(20260701, kcal: 2300, target: 2000, activity: 400).isOnTarget,
        isTrue,
      );
    });
  });

  group('HistorySummary', () {
    test('an all-empty span reads as zero, not a run of zero-kcal days', () {
      final s = HistorySummary.of([day(20260701), day(20260702)]);
      expect(s.periodDays, 2);
      expect(s.daysLogged, 0);
      expect(s.avgKcal, 0);
      expect(s.macroSplit, (carbs: 0.0, protein: 0.0, fat: 0.0));
    });

    test('averages only over days that were actually logged', () {
      final s = HistorySummary.of([
        day(20260701, kcal: 2000, target: 2000),
        day(20260702, kcal: 2400, target: 2000),
        day(20260703), // not logged — excluded
      ]);
      expect(s.periodDays, 3);
      expect(s.daysLogged, 2);
      expect(s.avgKcal, 2200);
      // (0 + 400) / 2
      expect(s.avgDeviation, 200);
    });

    test('adherence: within budget and not far under the base goal', () {
      final s = HistorySummary.of([
        day(20260701, kcal: 2000, target: 2000), // on the goal → yes
        day(20260702, kcal: 2200, target: 2000), // over (no activity) → no
        day(20260703, kcal: 1500, target: 2000), // >15% under base → no
        day(20260704, kcal: 1800, target: 2000), // 10% under → yes
        day(20260705, kcal: 2300, target: 2000, activity: 400), // within budget → yes
      ]);
      expect(s.adherentDays, 3);
    });

    test('macro split is the average plate by grams', () {
      final s = HistorySummary.of([
        day(20260701, kcal: 900, carbs: 100, protein: 50, fat: 50),
      ]);
      final split = s.macroSplit;
      expect(split.carbs, closeTo(0.5, 0.0001));
      expect(split.protein, closeTo(0.25, 0.0001));
      expect(split.fat, closeTo(0.25, 0.0001));
    });

    test('averages water and activity too', () {
      final s = HistorySummary.of([
        day(20260701, kcal: 100, water: 1000, activity: 200),
        day(20260702, kcal: 100, water: 2000, activity: 400),
      ]);
      expect(s.avgWaterMl, 1500);
      expect(s.avgActivityKcal, 300);
    });
  });

  group('HistoryRange', () {
    // A Wednesday, so the calendar week it belongs to reaches in both
    // directions and a rolling window can never be mistaken for one.
    const wednesday = DayKey(20260805);

    ({DayKey from, DayKey to}) week(
      HistoryRange range, [
      WeekStart start = WeekStart.monday,
    ]) => range.days(wednesday, start);

    test('defaults to the rolling window ending today', () {
      const range = HistoryRange(HistoryUnit.week);
      expect(range.isRolling, isTrue);
      expect(week(range), (from: const DayKey(20260730), to: wednesday));

      const month = HistoryRange(HistoryUnit.month);
      expect(week(month), (from: const DayKey(20260707), to: wednesday));
    });

    test('the rolling window ignores the week-start convention', () {
      const range = HistoryRange(HistoryUnit.week);
      expect(week(range, WeekStart.sunday), week(range, WeekStart.monday));
    });

    test('one step back is the previous whole calendar week', () {
      final range = const HistoryRange(HistoryUnit.week).step(-1, wednesday);
      // Monday-first: 27 Jul – 2 Aug.
      expect(week(range), (
        from: const DayKey(20260727),
        to: const DayKey(20260802),
      ));
      // Sunday-first shifts the same week by a day: 26 Jul – 1 Aug.
      expect(week(range, WeekStart.sunday), (
        from: const DayKey(20260726),
        to: const DayKey(20260801),
      ));
    });

    test('steps keep walking back a week at a time', () {
      final range = const HistoryRange(HistoryUnit.week)
          .step(-1, wednesday)
          .step(-1, wednesday)
          .step(-1, wednesday);
      expect(week(range), (
        from: const DayKey(20260713),
        to: const DayKey(20260719),
      ));
    });

    test('a month back is the whole previous month', () {
      final range = const HistoryRange(HistoryUnit.month).step(-1, wednesday);
      expect(week(range), (
        from: const DayKey(20260701),
        to: const DayKey(20260731),
      ));
    });

    test('month ends land on the real last day, leap years included', () {
      const inMarch = DayKey(20240315);
      final february = const HistoryRange(
        HistoryUnit.month,
      ).step(-1, inMarch).days(inMarch, WeekStart.monday);
      expect(february, (
        from: const DayKey(20240201),
        to: const DayKey(20240229),
      ));

      const inMay = DayKey(20260510);
      final april = const HistoryRange(
        HistoryUnit.month,
      ).step(-1, inMay).days(inMay, WeekStart.monday);
      expect(april, (from: const DayKey(20260401), to: const DayKey(20260430)));
    });

    test('paging back crosses the year boundary', () {
      const inJanuary = DayKey(20260115);
      final december = const HistoryRange(
        HistoryUnit.month,
      ).step(-1, inJanuary).days(inJanuary, WeekStart.monday);
      expect(december, (
        from: const DayKey(20251201),
        to: const DayKey(20251231),
      ));
    });

    test('forward is blocked at the rolling window and freed once paged back', () {
      const rolling = HistoryRange(HistoryUnit.week);
      expect(rolling.canStepForward(wednesday), isFalse);

      final back = rolling.step(-1, wednesday);
      expect(back.canStepForward(wednesday), isTrue);
      expect(back.step(1, wednesday).isRolling, isTrue);
    });

    test('switching unit drops the offset', () {
      final paged = const HistoryRange(HistoryUnit.week).step(-4, wednesday);
      expect(paged.isRolling, isFalse);
      expect(paged.withUnit(HistoryUnit.month).isRolling, isTrue);
    });

    test('a custom span survives a unit\'s stepping rules', () {
      final custom = const HistoryRange(
        HistoryUnit.week,
      ).withCustom(const DayKey(20260701), const DayKey(20260710));
      expect(custom.isRolling, isFalse);
      expect(week(custom), (
        from: const DayKey(20260701),
        to: const DayKey(20260710),
      ));
    });

    test('a custom span steps back by its own length', () {
      final custom = const HistoryRange(
        HistoryUnit.week,
      ).withCustom(const DayKey(20260701), const DayKey(20260710));
      // 10 days long, so one step back is 21–30 June.
      expect(week(custom.step(-1, wednesday)), (
        from: const DayKey(20260621),
        to: const DayKey(20260630),
      ));
    });

    test('stepping a custom span forward stops at today', () {
      // Ends two days short of today, so a full 10-day jump would overshoot
      // into the future; it may only move those two days.
      final custom = const HistoryRange(
        HistoryUnit.week,
      ).withCustom(const DayKey(20260725), const DayKey(20260803));
      expect(custom.canStepForward(wednesday), isTrue);
      expect(week(custom.step(1, wednesday)), (
        from: const DayKey(20260727),
        to: wednesday,
      ));
    });

    test('a custom span ending today cannot go forward', () {
      final custom = const HistoryRange(
        HistoryUnit.week,
      ).withCustom(const DayKey(20260801), wednesday);
      expect(custom.canStepForward(wednesday), isFalse);
    });
  });

  group('WeekStart', () {
    test('starts the week on the chosen day', () {
      // 2026-08-05 is a Wednesday.
      const wednesday = DayKey(20260805);
      expect(WeekStart.monday.startOfWeek(wednesday), const DayKey(20260803));
      expect(WeekStart.sunday.startOfWeek(wednesday), const DayKey(20260802));
    });

    test('a day that is already the start stays put', () {
      expect(
        WeekStart.monday.startOfWeek(const DayKey(20260803)),
        const DayKey(20260803),
      );
      expect(
        WeekStart.sunday.startOfWeek(const DayKey(20260802)),
        const DayKey(20260802),
      );
    });

    test('English counts from Sunday, everything else from Monday', () {
      expect(WeekStart.forLanguage('en'), WeekStart.sunday);
      expect(WeekStart.forLanguage('de'), WeekStart.monday);
    });
  });
}
