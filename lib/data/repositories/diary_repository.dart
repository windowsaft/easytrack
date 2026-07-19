import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/time/day_key.dart';
import '../../domain/day_summary.dart';
import '../db/user_database.dart';
import '../food/food_item.dart';

/// Reads and writes the daily diary.
class DiaryRepository {
  DiaryRepository(this._db);

  final UserDatabase _db;

  /// Watches one day, re-emitting whenever anything about it changes.
  Stream<DaySummary> watchDay(DayKey day) {
    final entries =
        (_db.select(_db.diaryEntries)
              ..where(
                (t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull(),
              )
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.loggedAt),
                // Same one-second-resolution tie-break as above, so entries
                // logged in quick succession keep a stable display order.
                (t) => OrderingTerm(expression: t.id),
              ]))
            .watch();

    final water =
        (_db.select(_db.waterLog)..where(
              (t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull(),
            ))
            .watch();

    final activity =
        (_db.select(_db.activityEntries)..where(
              (t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull(),
            ))
            .watch();

    return Rx.combine3(entries, water, activity, (
      List<DiaryEntry> diaryRows,
      List<WaterLogEntry> waterRows,
      List<ActivityEntry> activityRows,
    ) {
      final byMeal = <MealType, List<DiaryEntry>>{};
      for (final entry in diaryRows) {
        final meal = MealType.fromWire(entry.meal);
        (byMeal[meal] ??= []).add(entry);
      }

      return DaySummary(
        day: day,
        entriesByMeal: byMeal,
        waterMl: waterRows.fold(0, (sum, row) => sum + row.amountMl),
        activityKcalRaw: activityRows.fold(
          0.0,
          (sum, row) => sum + row.kcalBurnedRaw,
        ),
        // Each row keeps the factor that was in force when it was logged, so
        // changing the setting later does not silently rewrite past days.
        activityKcalAdjusted: activityRows.fold(
          0.0,
          (sum, row) => sum + row.kcalBurnedRaw * row.safetyFactor,
        ),
        target: DayTarget.fallback,
      );
    });
  }

  /// Logs a food into a meal.
  ///
  /// The nutrients are multiplied out and stored on the entry. This is what
  /// keeps a past log stable when a source later corrects the product, and what
  /// lets the reference pack be replaced wholesale.
  Future<String> addEntry({
    required DayKey day,
    required MealType meal,
    required FoodItem food,
    required double amountG,
    String? servingLabel,
    double? servingCount,
  }) async {
    final absolute = food.nutrients.forGrams(amountG);

    final maxSort =
        await (_db.selectOnly(_db.diaryEntries)
              ..addColumns([_db.diaryEntries.sortOrder.max()])
              ..where(
                _db.diaryEntries.loggedOn.equals(day.value) &
                    _db.diaryEntries.meal.equals(meal.wireName) &
                    _db.diaryEntries.deletedAt.isNull(),
              ))
            .map((row) => row.read(_db.diaryEntries.sortOrder.max()))
            .getSingleOrNull();

    final row = await _db
        .into(_db.diaryEntries)
        .insertReturning(
          DiaryEntriesCompanion.insert(
            loggedOn: day.value,
            meal: meal.wireName,
            sourceType: food.ref.source.wireName,
            sourceId: food.ref.id,
            nameSnapshot: food.name,
            brandSnapshot: Value(food.brand),
            amountG: amountG,
            servingLabel: Value(servingLabel),
            servingCount: Value(servingCount),
            sortOrder: Value((maxSort ?? -1) + 1),
            kcal: absolute.kcal,
            proteinG: absolute.proteinG,
            carbsG: absolute.carbsG,
            fatG: absolute.fatG,
            sugarG: Value(absolute.sugarG),
            fiberG: Value(absolute.fiberG),
            satFatG: Value(absolute.satFatG),
            saltG: Value(absolute.saltG),
          ),
        );

    return row.id;
  }

  /// Changes the logged amount, rescaling the stored nutrients.
  ///
  /// Rescales from the entry's own snapshot rather than re-reading the food, so
  /// editing an old entry cannot silently pull in changed source data.
  Future<void> updateAmount(String entryId, double newAmountG) async {
    final entry = await (_db.select(
      _db.diaryEntries,
    )..where((t) => t.id.equals(entryId))).getSingle();

    final factor = newAmountG / entry.amountG;
    double? scale(double? value) => value == null ? null : value * factor;

    await (_db.update(
      _db.diaryEntries,
    )..where((t) => t.id.equals(entryId))).write(
      DiaryEntriesCompanion(
        amountG: Value(newAmountG),
        kcal: Value(entry.kcal * factor),
        proteinG: Value(entry.proteinG * factor),
        carbsG: Value(entry.carbsG * factor),
        fatG: Value(entry.fatG * factor),
        sugarG: Value(scale(entry.sugarG)),
        fiberG: Value(scale(entry.fiberG)),
        satFatG: Value(scale(entry.satFatG)),
        saltG: Value(scale(entry.saltG)),
      ),
    );
  }

  /// Tombstones an entry. Rows are never physically deleted, so that a future
  /// sync can propagate the removal to other devices.
  Future<void> deleteEntry(String entryId) async {
    await (_db.update(_db.diaryEntries)..where((t) => t.id.equals(entryId)))
        .write(DiaryEntriesCompanion(deletedAt: Value(DateTime.now())));
  }

  Future<void> addWater({required DayKey day, required int amountMl}) async {
    await _db
        .into(_db.waterLog)
        .insert(
          WaterLogCompanion.insert(loggedOn: day.value, amountMl: amountMl),
        );
  }

  /// Removes the most recent water entry of the day, undoing a misplaced tap.
  Future<void> undoLastWater(DayKey day) async {
    final last =
        await (_db.select(_db.waterLog)
              ..where(
                (t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull(),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.loggedAt,
                  mode: OrderingMode.desc,
                ),
                // loggedAt is stored with one-second resolution, so two quick
                // taps tie and the "last" one becomes arbitrary. UUIDv7 keys
                // carry a millisecond timestamp in their high bits, so ordering
                // by id breaks the tie in true insertion order.
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (last == null) return;

    await (_db.update(_db.waterLog)..where((t) => t.id.equals(last.id))).write(
      WaterLogCompanion(deletedAt: Value(DateTime.now())),
    );
  }

  Future<void> addActivity({
    required DayKey day,
    required String label,
    required double kcalBurned,
    int? durationMin,
    double safetyFactor = 0.8,
  }) async {
    await _db
        .into(_db.activityEntries)
        .insert(
          ActivityEntriesCompanion.insert(
            loggedOn: day.value,
            label: label,
            kcalBurnedRaw: kcalBurned,
            durationMin: Value(durationMin),
            safetyFactor: Value(safetyFactor),
          ),
        );
  }

  /// Copies every entry of one meal to another day, for repeated meals.
  Future<int> copyMeal({
    required DayKey from,
    required DayKey to,
    required MealType meal,
    MealType? toMeal,
  }) async {
    final source =
        await (_db.select(_db.diaryEntries)..where(
              (t) =>
                  t.loggedOn.equals(from.value) &
                  t.meal.equals(meal.wireName) &
                  t.deletedAt.isNull(),
            ))
            .get();
    if (source.isEmpty) return 0;

    await _db.batch((batch) {
      batch.insertAll(_db.diaryEntries, [
        for (final entry in source)
          DiaryEntriesCompanion.insert(
            loggedOn: to.value,
            meal: (toMeal ?? meal).wireName,
            sourceType: entry.sourceType,
            sourceId: entry.sourceId,
            nameSnapshot: entry.nameSnapshot,
            brandSnapshot: Value(entry.brandSnapshot),
            amountG: entry.amountG,
            servingLabel: Value(entry.servingLabel),
            servingCount: Value(entry.servingCount),
            sortOrder: Value(entry.sortOrder),
            kcal: entry.kcal,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            sugarG: Value(entry.sugarG),
            fiberG: Value(entry.fiberG),
            satFatG: Value(entry.satFatG),
            saltG: Value(entry.saltG),
          ),
      ]);
    });

    return source.length;
  }
}

/// Minimal stream combiner, to avoid pulling in rxdart for one function.
abstract final class Rx {
  static Stream<R> combine3<A, B, C, R>(
    Stream<A> a,
    Stream<B> b,
    Stream<C> c,
    R Function(A, B, C) combine,
  ) {
    late A latestA;
    late B latestB;
    late C latestC;
    var hasA = false;
    var hasB = false;
    var hasC = false;

    late StreamController<R> controller;
    var subs = <StreamSubscription<void>>[];

    void emit() {
      if (hasA && hasB && hasC) {
        controller.add(combine(latestA, latestB, latestC));
      }
    }

    // Subscribe on listen rather than eagerly. Eager subscription would open
    // the three underlying database streams as soon as the summary stream was
    // built, whether or not anything ever listened, and leave them dangling.
    controller = StreamController<R>(
      onListen: () {
        subs = [
          a.listen((v) {
            latestA = v;
            hasA = true;
            emit();
          }, onError: controller.addError),
          b.listen((v) {
            latestB = v;
            hasB = true;
            emit();
          }, onError: controller.addError),
          c.listen((v) {
            latestC = v;
            hasC = true;
            emit();
          }, onError: controller.addError),
        ];
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
        subs = const [];
      },
    );

    return controller.stream;
  }
}
