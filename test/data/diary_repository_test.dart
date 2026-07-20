import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/repositories/diary_repository.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late DiaryRepository repository;

  const today = DayKey(20260719);

  /// Oats: 348 kcal, 13.2 g protein, 58.7 g carbs, 7 g fat per 100 g.
  final oats = FoodItem(
    ref: const FoodRef(FoodSourceType.bls, 'C133000'),
    name: 'Hafer Flocken',
    nutrients: const Nutrients(
      kcal: 348,
      proteinG: 13.2,
      carbsG: 58.7,
      fatG: 7,
      fiberG: 9.5,
    ),
  );

  final milk = FoodItem(
    ref: const FoodRef(FoodSourceType.bls, 'M111000'),
    name: 'Milch 3,5%',
    nutrients: const Nutrients(kcal: 64, proteinG: 3.3, carbsG: 4.7, fatG: 3.5),
  );

  setUp(() {
    db = UserDatabase.forTesting();
    repository = DiaryRepository(db, SettingsRepository(db));
  });
  tearDown(() => db.close());

  group('logging', () {
    test('scales nutrients to the logged amount', () async {
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 50,
      );

      final summary = await repository.watchDay(today).first;
      final consumed = summary.consumed;

      expect(consumed.kcal, closeTo(174, 0.01));
      expect(consumed.proteinG, closeTo(6.6, 0.01));
      expect(consumed.fatG, closeTo(3.5, 0.01));
    });

    test('stores a snapshot rather than a reference', () async {
      // The point: a later correction upstream must not rewrite this log.
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );

      final entry = (await db.select(db.diaryEntries).get()).single;
      expect(entry.kcal, closeTo(348, 0.01));
      expect(entry.nameSnapshot, 'Hafer Flocken');
      expect(entry.sourceId, 'C133000');
    });

    test('keeps meals separate and totals them together', () async {
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );
      await repository.addEntry(
        day: today,
        meal: MealType.lunch,
        food: milk,
        amountG: 200,
      );

      final summary = await repository.watchDay(today).first;

      expect(summary.entriesFor(MealType.breakfast), hasLength(1));
      expect(summary.entriesFor(MealType.lunch), hasLength(1));
      expect(summary.entriesFor(MealType.dinner), isEmpty);
      expect(summary.nutrientsFor(MealType.breakfast).kcal, closeTo(348, 0.01));
      expect(summary.nutrientsFor(MealType.lunch).kcal, closeTo(128, 0.01));
      expect(summary.consumed.kcal, closeTo(476, 0.01));
    });

    test('entries stay on their own day', () async {
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );
      await repository.addEntry(
        day: today.next,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );

      expect((await repository.watchDay(today).first).totalEntryCount, 1);
      expect((await repository.watchDay(today.next).first).totalEntryCount, 1);
      expect(
        (await repository.watchDay(today.previous).first).totalEntryCount,
        0,
      );
    });

    test('remembers the serving the user picked', () async {
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 60,
        servingLabel: 'Portion',
        servingCount: 2,
      );

      final entry = (await db.select(db.diaryEntries).get()).single;
      expect(entry.servingLabel, 'Portion');
      expect(entry.servingCount, 2);
      expect(entry.amountG, 60);
    });

    test('appends entries in order within a meal', () async {
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 50,
      );
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: milk,
        amountG: 200,
      );

      final entries = (await repository.watchDay(today).first).entriesFor(
        MealType.breakfast,
      );
      expect(entries.map((e) => e.nameSnapshot), [
        'Hafer Flocken',
        'Milch 3,5%',
      ]);
    });
  });

  group('editing', () {
    test('changing the amount rescales the stored nutrients', () async {
      final id = await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 50,
      );

      await repository.updateAmount(id, 100);

      final summary = await repository.watchDay(today).first;
      expect(summary.consumed.kcal, closeTo(348, 0.01));
      expect(summary.consumed.proteinG, closeTo(13.2, 0.01));
    });

    test('rescaling twice does not drift', () async {
      final id = await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 50,
      );

      await repository.updateAmount(id, 200);
      await repository.updateAmount(id, 50);

      final summary = await repository.watchDay(today).first;
      expect(summary.consumed.kcal, closeTo(174, 0.01));
    });

    test('optional nutrients rescale too', () async {
      final id = await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );
      await repository.updateAmount(id, 50);

      final entry = (await db.select(db.diaryEntries).get()).single;
      expect(entry.fiberG, closeTo(4.75, 0.01));
    });
  });

  group('deleting', () {
    test('removes the entry from the day but keeps the row', () async {
      final id = await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );

      await repository.deleteEntry(id);

      final summary = await repository.watchDay(today).first;
      expect(summary.totalEntryCount, 0);
      expect(summary.consumed.kcal, 0);

      // The tombstone survives so a future sync can propagate the delete.
      expect(await db.select(db.diaryEntries).get(), hasLength(1));
    });
  });

  group('water', () {
    test('sums the day and can be undone one tap at a time', () async {
      await repository.addWater(day: today, amountMl: 500);
      await repository.addWater(day: today, amountMl: 330);
      expect((await repository.watchDay(today).first).waterMl, 830);

      await repository.undoLastWater(today);
      expect((await repository.watchDay(today).first).waterMl, 500);
    });

    test('undo on an empty day is harmless', () async {
      await repository.undoLastWater(today);
      expect((await repository.watchDay(today).first).waterMl, 0);
    });
  });

  group('activity and budget', () {
    test('burned calories are discounted by the safety factor', () async {
      await repository.addActivity(
        day: today,
        label: 'Laufen',
        kcalBurned: 500,
        safetyFactor: 0.8,
      );

      final summary = await repository.watchDay(today).first;
      expect(summary.activityKcalRaw, 500);
      expect(summary.activityKcalAdjusted, closeTo(400, 0.01));
    });

    test('activity raises the day budget', () async {
      final before = await repository.watchDay(today).first;
      expect(before.budgetKcal, 2000); // fallback target

      await repository.addActivity(
        day: today,
        label: 'Radfahren',
        kcalBurned: 300,
      );

      final after = await repository.watchDay(today).first;
      expect(after.budgetKcal, closeTo(2240, 0.01)); // 2000 + 300 * 0.8
      expect(after.remainingKcal, closeTo(2240, 0.01));
    });

    test('remaining calories go negative past the budget', () async {
      // 700 g of oats is 2436 kcal, comfortably past a 2000 kcal target.
      await repository.addEntry(
        day: today,
        meal: MealType.dinner,
        food: oats,
        amountG: 700,
      );

      final summary = await repository.watchDay(today).first;
      expect(summary.isOverBudget, isTrue);
      expect(summary.remainingKcal, lessThan(0));
    });

    test('each entry keeps the factor in force when it was logged', () async {
      // Changing the setting later must not rewrite past days.
      await repository.addActivity(
        day: today,
        label: 'Alt',
        kcalBurned: 100,
        safetyFactor: 0.5,
      );
      await repository.addActivity(
        day: today,
        label: 'Neu',
        kcalBurned: 100,
        safetyFactor: 1.0,
      );

      final summary = await repository.watchDay(today).first;
      expect(summary.activityKcalAdjusted, closeTo(150, 0.01));
    });
  });

  group('copying a meal', () {
    test('duplicates every entry onto another day', () async {
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 50,
      );
      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: milk,
        amountG: 200,
      );

      final copied = await repository.copyMeal(
        from: today,
        to: today.next,
        meal: MealType.breakfast,
      );

      expect(copied, 2);
      final tomorrow = await repository.watchDay(today.next).first;
      expect(tomorrow.entriesFor(MealType.breakfast), hasLength(2));
      expect(
        tomorrow.consumed.kcal,
        closeTo((await repository.watchDay(today).first).consumed.kcal, 0.01),
      );
    });

    test('copying an empty meal does nothing', () async {
      expect(
        await repository.copyMeal(
          from: today,
          to: today.next,
          meal: MealType.dinner,
        ),
        0,
      );
    });
  });

  group('repeating a meal', () {
    test('copies the most recent earlier day with that meal', () async {
      // Breakfast two days ago, nothing yesterday.
      await repository.addEntry(
        day: today.previous.previous,
        meal: MealType.breakfast,
        food: oats,
        amountG: 50,
      );
      await repository.addEntry(
        day: today.previous.previous,
        meal: MealType.breakfast,
        food: milk,
        amountG: 200,
      );

      final copied = await repository.repeatMeal(
        to: today,
        meal: MealType.breakfast,
      );

      expect(copied, 2);
      expect(
        (await repository.watchDay(today).first).entriesFor(MealType.breakfast),
        hasLength(2),
      );
    });

    test('does nothing when no earlier day had that meal', () async {
      expect(await repository.repeatMeal(to: today, meal: MealType.dinner), 0);
    });

    test('ignores the target day itself and any later day', () async {
      await repository.addEntry(
        day: today.next,
        meal: MealType.lunch,
        food: oats,
        amountG: 50,
      );
      // Only a future lunch exists, so there is nothing earlier to repeat.
      expect(await repository.repeatMeal(to: today, meal: MealType.lunch), 0);
    });
  });

  group('live updates', () {
    test('the day stream re-emits when an entry is added', () async {
      final stream = repository.watchDay(today);
      final future = stream.firstWhere((s) => s.totalEntryCount == 1);

      await repository.addEntry(
        day: today,
        meal: MealType.breakfast,
        food: oats,
        amountG: 100,
      );

      final summary = await future.timeout(const Duration(seconds: 5));
      expect(summary.consumed.kcal, closeTo(348, 0.01));
    });
  });
}
