// drift exports isNull/isNotNull as SQL expression builders, which collide with
// the matchers of the same name.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:easytrack/data/db/user_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

void main() {
  late UserDatabase db;

  setUp(() => db = UserDatabase.forTesting());
  tearDown(() => db.close());

  Future<String> insertEntry({int day = 20260719, String meal = 'breakfast'}) {
    return db
        .into(db.diaryEntries)
        .insertReturning(
          DiaryEntriesCompanion.insert(
            loggedOn: day,
            meal: meal,
            sourceType: 'bls',
            sourceId: 'C133000',
            nameSnapshot: 'Hafer Flocken',
            amountG: 50,
            kcal: 174,
            proteinG: 6.61,
            carbsG: 29.35,
            fatG: 3.5,
          ),
        )
        .then((row) => row.id);
  }

  group('identity and sync metadata', () {
    test('assigns a UUIDv7 primary key automatically', () async {
      final id = await insertEntry();
      expect(id, hasLength(36));
      // Version nibble of a v7 UUID.
      expect(id[14], '7');
    });

    test('UUIDv7 keys sort chronologically by generation order', () async {
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await insertEntry());
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(List.of(ids)..sort(), ids);
    });

    test('new rows start dirty and unsynced', () async {
      final id = await insertEntry();
      final row = await (db.select(
        db.diaryEntries,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(row.dirty, isTrue);
      expect(row.syncRev, 0);
      expect(row.deletedAt, isNull);
      expect(row.createdAt, isNotNull);
    });
  });

  group('sync-stamp trigger', () {
    test('an update that forgets the metadata is stamped anyway', () async {
      final id = await insertEntry();

      // Simulate a sync having taken the row: clean, and at revision 3.
      await db.customStatement(
        'UPDATE diary_entries SET dirty = 0, sync_rev = 3 WHERE id = ?',
        [id],
      );
      final synced = await (db.select(
        db.diaryEntries,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(synced.dirty, isFalse, reason: 'setup: row should be clean');

      // A write path that only touches the payload — exactly the mistake the
      // trigger exists to catch.
      await db.customStatement(
        'UPDATE diary_entries SET amount_g = 75 WHERE id = ?',
        [id],
      );

      final after = await (db.select(
        db.diaryEntries,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(after.amountG, 75);
      expect(
        after.dirty,
        isTrue,
        reason: 'trigger must re-mark the row for upload',
      );
      expect(
        after.updatedAt.isAfter(synced.updatedAt) ||
            after.updatedAt.isAtSameMomentAs(synced.updatedAt),
        isTrue,
      );
    });

    test('a sync may clear the dirty flag without it snapping back', () async {
      final id = await insertEntry();

      // Marking a row as pushed touches only the sync columns. If the trigger
      // fired here, no row could ever be recorded as uploaded.
      await db.customStatement(
        'UPDATE diary_entries SET dirty = 0 WHERE id = ?',
        [id],
      );

      final row = await (db.select(
        db.diaryEntries,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.dirty, isFalse);
    });

    test('an explicit updated_at is left alone', () async {
      final id = await insertEntry();
      // A sync pulling server state down sets updated_at itself; the trigger
      // must not clobber it or the row would immediately look dirty again.
      const serverTime = 1700000000;
      await db.customStatement(
        'UPDATE diary_entries SET amount_g = 10, updated_at = ?, dirty = 0 '
        'WHERE id = ?',
        [serverTime, id],
      );

      final row = await (db.select(
        db.diaryEntries,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.updatedAt.millisecondsSinceEpoch ~/ 1000, serverTime);
      expect(row.dirty, isFalse);
    });
  });

  group('soft delete', () {
    test('tombstoned rows remain queryable for a future sync', () async {
      final id = await insertEntry();
      await (db.update(db.diaryEntries)..where((t) => t.id.equals(id))).write(
        DiaryEntriesCompanion(deletedAt: Value(DateTime.now())),
      );

      final all = await db.select(db.diaryEntries).get();
      expect(all, hasLength(1), reason: 'row must survive physically');

      final live = await (db.select(
        db.diaryEntries,
      )..where((t) => t.deletedAt.isNull())).get();
      expect(live, isEmpty, reason: 'but must not appear in normal reads');
    });

    test('the weight-per-day rule ignores tombstoned rows', () async {
      Future<String> logWeight(double kg) => db
          .into(db.weightLog)
          .insertReturning(
            WeightLogCompanion.insert(measuredOn: 20260719, weightKg: kg),
          )
          .then((r) => r.id);

      final first = await logWeight(80);
      // A second live measurement on the same day is rejected.
      await expectLater(logWeight(81), throwsA(isA<SqliteException>()));

      // But after deleting the first, the day is free again.
      await (db.update(db.weightLog)..where((t) => t.id.equals(first))).write(
        WeightLogCompanion(deletedAt: Value(DateTime.now())),
      );
      await expectLater(logWeight(81), completes);
    });
  });

  group('referential integrity', () {
    test('deleting a recipe cascades to its ingredients', () async {
      final recipe = await db
          .into(db.recipes)
          .insertReturning(RecipesCompanion.insert(name: 'Chili'));
      await db
          .into(db.recipeIngredients)
          .insert(
            RecipeIngredientsCompanion.insert(
              recipeId: recipe.id,
              nameSnapshot: 'Kidneybohnen',
              amountG: 400,
              sourceType: 'bls',
              sourceId: 'G123456',
              kcal: 380,
              proteinG: 26,
              carbsG: 60,
              fatG: 2,
            ),
          );

      expect(await db.select(db.recipeIngredients).get(), hasLength(1));

      await (db.delete(db.recipes)..where((t) => t.id.equals(recipe.id))).go();

      expect(
        await db.select(db.recipeIngredients).get(),
        isEmpty,
        reason: 'foreign keys must be enabled for the cascade to fire',
      );
    });
  });

  group('diary queries', () {
    test('entries are retrievable by local day and meal', () async {
      await insertEntry(day: 20260718, meal: 'dinner');
      await insertEntry(day: 20260719, meal: 'breakfast');
      await insertEntry(day: 20260719, meal: 'breakfast');
      await insertEntry(day: 20260719, meal: 'lunch');

      final breakfast =
          await (db.select(db.diaryEntries)..where(
                (t) =>
                    t.loggedOn.equals(20260719) &
                    t.meal.equals('breakfast') &
                    t.deletedAt.isNull(),
              ))
              .get();

      expect(breakfast, hasLength(2));
    });

    test('a date range selects exactly the intended days', () async {
      await insertEntry(day: 20260630);
      await insertEntry(day: 20260701);
      await insertEntry(day: 20260731);
      await insertEntry(day: 20260801);

      final july = await (db.select(
        db.diaryEntries,
      )..where((t) => t.loggedOn.isBetweenValues(20260701, 20260731))).get();

      expect(july, hasLength(2));
    });
  });
}
