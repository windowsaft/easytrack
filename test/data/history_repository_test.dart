import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/repositories/diary_repository.dart';
import 'package:easytrack/data/repositories/history_repository.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late HistoryRepository history;
  late DiaryRepository diary;

  const d1 = DayKey(20260718);
  const d2 = DayKey(20260719);
  const d3 = DayKey(20260720);

  final oats = FoodItem(
    ref: const FoodRef(FoodSourceType.bls, 'C133000'),
    name: 'Hafer',
    nutrients: const Nutrients(
      kcal: 348,
      proteinG: 13.2,
      carbsG: 58.7,
      fatG: 7,
    ),
  );

  setUp(() {
    db = UserDatabase.forTesting();
    history = HistoryRepository(db);
    diary = DiaryRepository(db, SettingsRepository(db));
  });
  tearDown(() => db.close());

  test('rolls a day up across food, water and activity', () async {
    await diary.addEntry(
      day: d3,
      meal: MealType.breakfast,
      food: oats,
      amountG: 100,
    );
    await diary.addWater(day: d3, amountMl: 500);
    await diary.addActivity(
      day: d3,
      label: 'Laufen',
      kcalBurned: 200,
      safetyFactor: 0.8,
    );

    final rows = await history.watchRange(d3, d3).first;
    expect(rows, hasLength(1));
    final day = rows.single;
    expect(day.kcal, closeTo(348, 0.01));
    expect(day.carbsG, closeTo(58.7, 0.01));
    expect(day.waterMl, 500);
    expect(day.activityKcal, closeTo(160, 0.01));
    // No target rows → the default.
    expect(day.targetKcal, SettingsRepository.defaultKcal);
  });

  test('emits every day in the range, gaps as zero-intake days', () async {
    await diary.addEntry(
      day: d1,
      meal: MealType.breakfast,
      food: oats,
      amountG: 100,
    );
    await diary.addEntry(
      day: d3,
      meal: MealType.dinner,
      food: oats,
      amountG: 100,
    );

    final rows = await history.watchRange(d1, d3).first;
    expect(rows.map((r) => r.day.value), [d1.value, d2.value, d3.value]);
    expect(rows[0].hasData, isTrue);
    expect(rows[1].hasData, isFalse); // the gap
    expect(rows[2].hasData, isTrue);
  });

  test('resolves the history-preserving target per day', () async {
    // A goal of 1800 from d1, raised to 2200 effective d3.
    await db
        .into(db.targets)
        .insert(TargetsCompanion.insert(effectiveFrom: d1.value, kcal: 1800));
    await db
        .into(db.targets)
        .insert(TargetsCompanion.insert(effectiveFrom: d3.value, kcal: 2200));

    final rows = await history.watchRange(d1, d3).first;
    expect(rows[0].targetKcal, 1800); // d1
    expect(rows[1].targetKcal, 1800); // d2 still on the old goal
    expect(rows[2].targetKcal, 2200); // d3 onward
  });
}
