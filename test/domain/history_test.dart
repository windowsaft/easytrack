import 'package:easytrack/core/time/day_key.dart';
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
}
