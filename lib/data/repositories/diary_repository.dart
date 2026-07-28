import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/time/day_key.dart';
import '../../domain/day_summary.dart';
import '../db/user_database.dart';
import '../food/food_item.dart';
import 'settings_repository.dart';

/// Reads and writes the daily diary.
class DiaryRepository {
  DiaryRepository(this._db, this._settings);

  final UserDatabase _db;

  /// Targets and the profile are read through the settings repository rather
  /// than re-queried here, so there is exactly one definition of "the target in
  /// force on a day".
  final SettingsRepository _settings;

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

    final target = _settings.watchTargetFor(day);
    final profile = _settings.watchProfile();

    return Rx.combineLatest([entries, water, activity, target, profile], (
      values,
    ) {
      final diaryRows = values[0]! as List<DiaryEntry>;
      final waterRows = values[1]! as List<WaterLogEntry>;
      final activityRows = values[2]! as List<ActivityEntry>;
      final targetRow = values[3] as TargetRow?;
      final profileRow = values[4] as UserProfileRow?;

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
        // Falls back per field rather than wholesale: the activity toggle is
        // profile state and stays meaningful even before a target is set.
        target: DayTarget(
          kcal: targetRow?.kcal ?? DayTarget.fallback.kcal,
          proteinG: targetRow?.proteinG,
          carbsG: targetRow?.carbsG,
          fatG: targetRow?.fatG,
          waterMl: targetRow?.waterMl ?? DayTarget.fallback.waterMl,
          activityAddsToBudget: profileRow?.activityAddsToBudget ?? true,
        ),
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
            unit: Value(food.measure.wire),
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
  Future<void> updateAmount(String entryId, double newAmountG) =>
      _rescaleEntry(entryId, newAmountG, const DiaryEntriesCompanion());

  /// Re-portions a logged entry: a new amount plus the serving it was picked as.
  ///
  /// Like [updateAmount] it rescales the stored nutrient snapshot rather than
  /// re-reading the food, but it also rewrites the serving label/count so a row
  /// edited down to a bare gram amount stops claiming its old "2 × Portion".
  Future<void> editEntry({
    required String entryId,
    required double amountG,
    String? servingLabel,
    double? servingCount,
  }) => _rescaleEntry(
    entryId,
    amountG,
    DiaryEntriesCompanion(
      servingLabel: Value(servingLabel),
      servingCount: Value(servingCount),
    ),
  );

  /// Writes [newAmountG] and the rescaled snapshot, merging any [extra] columns
  /// (e.g. the serving fields) into the same update so the day's stream emits
  /// once, not twice.
  Future<void> _rescaleEntry(
    String entryId,
    double newAmountG,
    DiaryEntriesCompanion extra,
  ) async {
    final entry = await (_db.select(
      _db.diaryEntries,
    )..where((t) => t.id.equals(entryId))).getSingle();

    final factor = newAmountG / entry.amountG;
    double? scale(double? value) => value == null ? null : value * factor;

    await (_db.update(
      _db.diaryEntries,
    )..where((t) => t.id.equals(entryId))).write(
      extra.copyWith(
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

  /// Sets the day's water total, as the eight-cup meter on the diary does.
  ///
  /// The meter is a level, not a stream of events, so lowering it cannot be
  /// expressed as another log row without inventing a negative drink. Raising
  /// it appends the difference; lowering it tombstones the day and writes a
  /// single row for the new total. Individual sip timestamps are lost on the
  /// way down, which is a fair trade for a control whose whole premise is that
  /// the day has one water level.
  Future<void> setWater({required DayKey day, required int amountMl}) async {
    final rows = await (_db.select(
      _db.waterLog,
    )..where((t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull())).get();
    final current = rows.fold(0, (sum, row) => sum + row.amountMl);
    if (amountMl == current) return;

    if (amountMl > current) {
      await addWater(day: day, amountMl: amountMl - current);
      return;
    }

    await _db.transaction(() async {
      await (_db.update(_db.waterLog)
            ..where((t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull()))
          .write(WaterLogCompanion(deletedAt: Value(DateTime.now())));
      if (amountMl > 0) {
        await addWater(day: day, amountMl: amountMl);
      }
    });
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

  /// The most recently logged foods, one row per distinct food.
  ///
  /// Returns diary entries rather than [FoodItem]s on purpose: an entry already
  /// carries the name, the portion and the nutrient snapshot the user chose
  /// last time, so re-logging one needs no lookup in the reference database and
  /// cannot be affected by the pack having been replaced since.
  Stream<List<DiaryEntry>> watchRecentFoods({int limit = 30}) => _db
      .customSelect(
        '''
        SELECT * FROM diary_entries
        WHERE deleted_at IS NULL
        GROUP BY source_type, source_id
        HAVING logged_at = MAX(logged_at)
        ORDER BY logged_at DESC
        LIMIT ?1
        ''',
        variables: [Variable.withInt(limit)],
        readsFrom: {_db.diaryEntries},
      )
      .map(_db.diaryEntries.mapFromRow)
      .watch()
      // mapFromRow is asynchronous, so the query yields a list of futures.
      .asyncMap(Future.wait);

  /// Logs a previous entry again, with the same portion and snapshot.
  Future<void> relogEntry({
    required DiaryEntry source,
    required DayKey day,
    required MealType meal,
  }) async {
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

    await _db
        .into(_db.diaryEntries)
        .insert(
          DiaryEntriesCompanion.insert(
            loggedOn: day.value,
            meal: meal.wireName,
            sourceType: source.sourceType,
            sourceId: source.sourceId,
            nameSnapshot: source.nameSnapshot,
            brandSnapshot: Value(source.brandSnapshot),
            amountG: source.amountG,
            unit: Value(source.unit),
            servingLabel: Value(source.servingLabel),
            servingCount: Value(source.servingCount),
            sortOrder: Value((maxSort ?? -1) + 1),
            kcal: source.kcal,
            proteinG: source.proteinG,
            carbsG: source.carbsG,
            fatG: source.fatG,
            sugarG: Value(source.sugarG),
            fiberG: Value(source.fiberG),
            satFatG: Value(source.satFatG),
            saltG: Value(source.saltG),
          ),
        );
  }

  /// The day's activity entries, newest last.
  Stream<List<ActivityEntry>> watchActivity(DayKey day) =>
      (_db.select(_db.activityEntries)
            ..where((t) => t.loggedOn.equals(day.value) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.loggedAt)]))
          .watch();

  Future<void> deleteActivity(String entryId) async {
    await (_db.update(_db.activityEntries)..where((t) => t.id.equals(entryId)))
        .write(ActivityEntriesCompanion(deletedAt: Value(DateTime.now())));
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
            unit: Value(entry.unit),
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

  /// Repeats a meal the user has eaten before: finds the most recent day
  /// *before* [to] that had entries for [meal] and copies them onto [to].
  ///
  /// Returns the number of entries copied, or 0 if no earlier day had that meal
  /// — the "repeat my usual breakfast" action, without the user hunting for the
  /// day to copy from.
  Future<int> repeatMeal({required DayKey to, required MealType meal}) async {
    final source =
        await (_db.selectOnly(_db.diaryEntries)
              ..addColumns([_db.diaryEntries.loggedOn])
              ..where(
                _db.diaryEntries.meal.equals(meal.wireName) &
                    _db.diaryEntries.loggedOn.isSmallerThanValue(to.value) &
                    _db.diaryEntries.deletedAt.isNull(),
              )
              ..orderBy([
                OrderingTerm(
                  expression: _db.diaryEntries.loggedOn,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .map((row) => row.read(_db.diaryEntries.loggedOn))
            .getSingleOrNull();
    if (source == null) return 0;

    return copyMeal(from: DayKey(source), to: to, meal: meal);
  }
}

/// Minimal stream combiner, to avoid pulling in rxdart for one function.
abstract final class Rx {
  /// Emits once every source has produced a value, and on every value after.
  ///
  /// Untyped in its elements because the sources have different types; callers
  /// cast positionally. A fixed-arity generic version was replaced by this one
  /// when the day summary grew past three inputs — each new arity meant copying
  /// the whole subscription dance again.
  static Stream<R> combineLatest<R>(
    List<Stream<Object?>> sources,
    R Function(List<Object?> values) combine,
  ) {
    final latest = List<Object?>.filled(sources.length, null);
    final seen = List<bool>.filled(sources.length, false);
    var pending = sources.length;

    late StreamController<R> controller;
    var subs = <StreamSubscription<void>>[];

    // Subscribe on listen rather than eagerly. Eager subscription would open
    // the underlying database streams as soon as the summary stream was built,
    // whether or not anything ever listened, and leave them dangling.
    controller = StreamController<R>(
      onListen: () {
        subs = [
          for (var i = 0; i < sources.length; i++)
            sources[i].listen((value) {
              latest[i] = value;
              if (!seen[i]) {
                seen[i] = true;
                pending--;
              }
              if (pending == 0) {
                // Guard the combiner: it runs here inside a source's onData, so
                // a throw (e.g. a diary row with an unrecognised meal, as a
                // hand-edited or foreign import can carry) would escape as an
                // uncaught zone error and the stream would simply never emit —
                // an indefinite loading spinner. Routing it to addError instead
                // surfaces it as the screen's visible "Fehler beim Laden".
                final R combined;
                try {
                  combined = combine(latest);
                } catch (error, stack) {
                  controller.addError(error, stack);
                  return;
                }
                controller.add(combined);
              }
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
