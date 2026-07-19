import 'package:drift/drift.dart';

import '../../core/ids/uuid_v7.dart';

/// Metadata carried by every user-owned row so that a sync layer can be added
/// later without a migration that touches every table.
///
/// Nothing writes [syncRev] yet — it exists so the columns are already there
/// when a server arrives. Backfilling identity columns onto tables that already
/// hold a year of diary data is exactly the kind of migration worth avoiding.
mixin SyncableTable on Table {
  /// UUIDv7 primary key: globally unique without a server, time-ordered for
  /// index locality.
  TextColumn get id => text().clientDefault(newId)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Soft-delete tombstone. Rows are never physically removed, because a hard
  /// delete cannot be communicated to a peer that has not synced yet.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Server revision; 0 means never synced.
  IntColumn get syncRev => integer().withDefault(const Constant(0))();

  /// Has local changes not yet pushed.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Nutrients per 100 g. Reused by custom foods and by the online-product cache.
mixin Per100gColumns on Table {
  RealColumn get kcal => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbsG => real()();
  RealColumn get fatG => real()();
  RealColumn get sugarG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get satFatG => real().nullable()();
  RealColumn get saltG => real().nullable()();
}

/// Absolute nutrients for a logged amount — already multiplied out.
///
/// Diary entries and recipe ingredients snapshot these at the moment of
/// logging. If Open Food Facts corrects a product's calories next month, past
/// logs must keep the numbers they were recorded with, and the whole reference
/// database must stay swappable without rewriting user history.
mixin NutrientSnapshotColumns on Table {
  RealColumn get kcal => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbsG => real()();
  RealColumn get fatG => real()();
  RealColumn get sugarG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get satFatG => real().nullable()();
  RealColumn get saltG => real().nullable()();
}

/// Identifies a food in any source. See `core/nutrition/food_ref.dart`.
mixin FoodRefColumns on Table {
  TextColumn get sourceType => text().withLength(min: 1, max: 16)();
  TextColumn get sourceId => text().withLength(min: 1, max: 128)();
}

@DataClassName('CustomFood')
class CustomFoods extends Table with SyncableTable, Per100gColumns {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get brand => text().nullable().withLength(max: 120)();
  TextColumn get barcode => text().nullable().withLength(max: 32)();

  /// Normalized search text, kept in sync by the repository on write.
  TextColumn get searchText => text().withDefault(const Constant(''))();

  RealColumn get defaultServingG => real().nullable()();
  TextColumn get defaultServingLabel => text().nullable().withLength(max: 60)();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  /// If this food was forked from a reference entry, where it came from.
  TextColumn get originSourceType => text().nullable().withLength(max: 16)();
  TextColumn get originSourceId => text().nullable().withLength(max: 128)();
}

@DataClassName('Recipe')
class Recipes extends Table with SyncableTable {
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get searchText => text().withDefault(const Constant(''))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  /// Weight of the finished dish, when it differs from the sum of ingredients.
  ///
  /// Cooking drives off water, so a 1400 g raw batch may yield 1100 g of food.
  /// When set, portions scale against this instead of the ingredient sum, which
  /// is the difference between an honest and a misleading calorie count.
  RealColumn get cookedWeightG => real().nullable()();
}

@DataClassName('RecipeIngredient')
class RecipeIngredients extends Table
    with SyncableTable, FoodRefColumns, NutrientSnapshotColumns {
  TextColumn get recipeId =>
      text().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get nameSnapshot => text().withLength(min: 1, max: 200)();
  RealColumn get amountG => real()();
}

@DataClassName('DiaryEntry')
class DiaryEntries extends Table
    with SyncableTable, FoodRefColumns, NutrientSnapshotColumns {
  /// Local calendar day as yyyymmdd. See `core/time/day_key.dart`.
  IntColumn get loggedOn => integer()();

  /// Ordering within a meal, and a record of when it was actually eaten.
  DateTimeColumn get loggedAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get meal => text().withLength(min: 1, max: 16)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get nameSnapshot => text().withLength(min: 1, max: 200)();
  TextColumn get brandSnapshot => text().nullable().withLength(max: 120)();

  /// Always grams internally, so all arithmetic is unit-free.
  RealColumn get amountG => real()();

  /// What the user actually picked ("2 Scheiben"), preserved so that reopening
  /// an entry shows their choice rather than a bare gram count.
  TextColumn get servingLabel => text().nullable().withLength(max: 60)();
  RealColumn get servingCount => real().nullable()();
}

@DataClassName('WaterLogEntry')
class WaterLog extends Table with SyncableTable {
  IntColumn get loggedOn => integer()();
  DateTimeColumn get loggedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get amountMl => integer()();
  TextColumn get drinkType =>
      text().withLength(max: 16).withDefault(const Constant('water'))();
}

@DataClassName('ActivityEntry')
class ActivityEntries extends Table with SyncableTable {
  IntColumn get loggedOn => integer()();
  DateTimeColumn get loggedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get label => text().withLength(min: 1, max: 120)();
  IntColumn get durationMin => integer().nullable()();

  /// Calories as entered by the user, before the safety factor is applied.
  ///
  /// The raw figure is stored rather than the adjusted one so that changing the
  /// safety factor later re-evaluates history consistently instead of baking an
  /// old factor into old rows.
  RealColumn get kcalBurnedRaw => real()();

  /// The factor in force when this entry was created, so historical days stay
  /// reproducible even after the setting changes.
  RealColumn get safetyFactor => real().withDefault(const Constant(0.8))();
}

@DataClassName('WeightEntry')
class WeightLog extends Table with SyncableTable {
  IntColumn get measuredOn => integer()();
  RealColumn get weightKg => real()();
  RealColumn get bodyFatPct => real().nullable()();
  TextColumn get note => text().nullable()();
}

@DataClassName('UserProfileRow')
class UserProfile extends Table with SyncableTable {
  DateTimeColumn get birthDate => dateTime().nullable()();

  /// 'male' | 'female' — drives the Mifflin-St Jeor constant. Users who prefer
  /// not to say can set a manual calorie target instead.
  TextColumn get sex => text().nullable().withLength(max: 16)();
  RealColumn get heightCm => real().nullable()();
  TextColumn get activityLevel =>
      text().withLength(max: 24).withDefault(const Constant('moderate'))();
  TextColumn get goal =>
      text().withLength(max: 16).withDefault(const Constant('maintain'))();
  RealColumn get rateKgPerWeek => real().withDefault(const Constant(0))();

  /// Applied to logged activity before it is added to the day's budget.
  RealColumn get activitySafetyFactor =>
      real().withDefault(const Constant(0.8))();

  /// Whether logged activity increases the day's calorie budget at all.
  BoolColumn get activityAddsToBudget =>
      boolean().withDefault(const Constant(true))();
}

/// Daily targets, kept as history rather than as columns on the profile.
///
/// The target in force on a given day is the row with the greatest
/// [effectiveFrom] not after that day. Storing a single current value would
/// silently rewrite past progress every time the goal changes.
@DataClassName('TargetRow')
class Targets extends Table with SyncableTable {
  IntColumn get effectiveFrom => integer()();
  RealColumn get kcal => real()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  IntColumn get waterMl => integer().withDefault(const Constant(2000))();

  /// False once the user overrides the computed value by hand.
  BoolColumn get isAuto => boolean().withDefault(const Constant(true))();
}

/// Products fetched from the Open Food Facts API.
///
/// Lives in the user database, not the reference pack, so that replacing the
/// pack cannot discard products this user scanned.
@DataClassName('CachedProduct')
class OffCache extends Table with SyncableTable, Per100gColumns {
  TextColumn get barcode => text().withLength(min: 4, max: 32)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get brand => text().nullable().withLength(max: 120)();
  TextColumn get searchText => text().withDefault(const Constant(''))();
  RealColumn get servingSizeG => real().nullable()();
  DateTimeColumn get fetchedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {barcode},
  ];
}

/// Foods the user pinned, across any source.
@DataClassName('PinnedFood')
class PinnedFoods extends Table with SyncableTable, FoodRefColumns {
  TextColumn get nameSnapshot => text().withLength(min: 1, max: 200)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sourceType, sourceId},
  ];
}

/// Sync bookkeeping. Unused until a server exists; present so that adding one
/// does not require a migration.
@DataClassName('SyncCursorRow')
class SyncCursors extends Table {
  TextColumn get entity => text().withLength(min: 1, max: 64)();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  IntColumn get lastPushedRev => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {entity};
}
