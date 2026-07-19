import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Referenced by generated code: the SyncableTable mixin uses newId as the
// clientDefault for every primary key, and the generated part file resolves
// that name against this library's imports.
// ignore: unused_import
import '../../core/ids/uuid_v7.dart';
import 'tables.dart';

part 'user_database.g.dart';

@DriftDatabase(
  tables: [
    CustomFoods,
    Recipes,
    RecipeIngredients,
    DiaryEntries,
    WaterLog,
    ActivityEntries,
    WeightLog,
    UserProfile,
    Targets,
    OffCache,
    PinnedFoods,
    SyncCursors,
  ],
)
class UserDatabase extends _$UserDatabase {
  UserDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// In-memory instance for tests.
  UserDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() => driftDatabase(name: 'user');

  /// Tables carrying [SyncableTable]. Used to generate the sync-stamp triggers.
  static const _syncableTables = <String>[
    'custom_foods',
    'recipes',
    'recipe_ingredients',
    'diary_entries',
    'water_log',
    'activity_entries',
    'weight_log',
    'user_profile',
    'targets',
    'off_cache',
    'pinned_foods',
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
      await _createSyncTriggers();
    },
    beforeOpen: (details) async {
      // SQLite disables foreign keys per connection by default, and recipe
      // ingredients depend on the cascade from their recipe.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndexes() async {
    // The diary is almost always read one day at a time, grouped by meal.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_diary_day '
      'ON diary_entries (logged_on, meal, sort_order)',
    );
    // Powers the "recently eaten" ranking boost in search.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_diary_food '
      'ON diary_entries (source_type, source_id, logged_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_water_day ON water_log (logged_on)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_day '
      'ON activity_entries (logged_on)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipe_ingredients '
      'ON recipe_ingredients (recipe_id, sort_order)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_off_cache_barcode '
      'ON off_cache (barcode)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_custom_foods_barcode '
      'ON custom_foods (barcode) WHERE barcode IS NOT NULL',
    );
    // At most one weight measurement per day, ignoring tombstoned rows.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_weight_day '
      'ON weight_log (measured_on) WHERE deleted_at IS NULL',
    );
  }

  /// Stamps `updated_at` and `dirty` on every update, in the database itself.
  ///
  /// Enforcing this in repositories instead would mean the one write path that
  /// forgets produces a row a future sync never uploads — a bug that surfaces
  /// months later, on a device restore, as silently missing data.
  ///
  /// The `WHEN` guard has to distinguish a payload edit from sync bookkeeping,
  /// and it also stops the trigger from recursing into itself:
  ///
  /// - `updated_at` unchanged — an explicit timestamp means the caller is
  ///   already managing sync state, e.g. applying server state on pull.
  /// - `sync_rev` unchanged — a new revision means the row was just pushed.
  /// - not a clean transition — clearing `dirty` is how a sync records that it
  ///   uploaded the row. Without this clause the flag could never be cleared,
  ///   and every row would look permanently unsynced.
  ///
  /// What remains is exactly the case worth catching: someone changed the data
  /// and left the metadata alone.
  Future<void> _createSyncTriggers() async {
    for (final table in _syncableTables) {
      await customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_${table}_sync_stamp
AFTER UPDATE ON $table
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
  AND NEW.sync_rev = OLD.sync_rev
  AND NOT (OLD.dirty = 1 AND NEW.dirty = 0)
BEGIN
  UPDATE $table
     SET updated_at = CAST(strftime('%s', 'now') AS INTEGER),
         dirty = 1
   WHERE id = NEW.id;
END;
''');
    }
  }
}
