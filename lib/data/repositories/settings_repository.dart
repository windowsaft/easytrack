import 'package:drift/drift.dart';

import '../../core/time/day_key.dart';
import '../../domain/tdee.dart';
import '../db/user_database.dart';

/// Reads and writes the profile and the daily targets behind the Settings
/// screen.
///
/// Targets are append-only history rather than mutable columns: the row in
/// force on a day is the newest one not after it. Editing a single current
/// value would rewrite what past days were measured against, turning every
/// historical chart into a lie the moment the user changes their goal.
class SettingsRepository {
  SettingsRepository(this._db);

  final UserDatabase _db;

  /// Defaults used until the user has been through Settings.
  ///
  /// 0.8 rather than the 0.85 shown in the design handoff: it is the value in
  /// `docs/plan.md`, it is already the column default in the schema, and rows
  /// written before this screen existed carry it. Changing it would need a
  /// migration to stay consistent with history for no real benefit — the point
  /// of the screen is that the number is adjustable.
  static const defaultSafetyFactor = 0.8;
  static const defaultKcal = 2000.0;
  static const defaultWaterMl = 2000;
  static const defaultWaterCupMl = 250;

  // ---------------------------------------------------------------- profile

  /// The profile row, or null before one has been created.
  Stream<UserProfileRow?> watchProfile() =>
      (_db.select(_db.userProfile)
            ..where((t) => t.deletedAt.isNull())
            ..limit(1))
          .watchSingleOrNull();

  Future<UserProfileRow> _ensureProfile() async {
    final existing =
        await (_db.select(_db.userProfile)
              ..where((t) => t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing;

    return _db
        .into(_db.userProfile)
        .insertReturning(const UserProfileCompanion());
  }

  /// Scales manual burn entries. Clamped because a factor above 1 would inflate
  /// the budget and a factor of 0 would make the activity screen pointless.
  Future<void> setSafetyFactor(double factor) async {
    final profile = await _ensureProfile();
    await (_db.update(
      _db.userProfile,
    )..where((t) => t.id.equals(profile.id))).write(
      UserProfileCompanion(activitySafetyFactor: Value(factor.clamp(0.1, 1.0))),
    );
  }

  Future<void> setActivityAddsToBudget({required bool value}) async {
    final profile = await _ensureProfile();
    await (_db.update(_db.userProfile)..where((t) => t.id.equals(profile.id)))
        .write(UserProfileCompanion(activityAddsToBudget: Value(value)));
  }

  /// The volume of one water-meter bar. Clamped to sane pour sizes so the meter
  /// can never end up with a zero-width or absurd bar count.
  Future<void> setWaterCupMl(int ml) async {
    final profile = await _ensureProfile();
    await (_db.update(_db.userProfile)..where((t) => t.id.equals(profile.id)))
        .write(UserProfileCompanion(waterCupMl: Value(ml.clamp(50, 1000))));
  }

  /// The latest recorded body weight, or null if never weighed.
  ///
  /// Read from the weight log rather than a profile column so that the single
  /// source of truth for weight is the same table the trend chart will use.
  Stream<double?> watchLatestWeightKg() =>
      (_db.select(_db.weightLog)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.measuredOn,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(1))
          .watchSingleOrNull()
          .map((row) => row?.weightKg);

  /// The full weight history, oldest first — the series the trend chart plots.
  Stream<List<WeightEntry>> watchWeightLog() =>
      (_db.select(_db.weightLog)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.measuredOn)]))
          .watch();

  /// Records today's weight, replacing any earlier reading for the same day.
  Future<void> recordWeight(double kg) =>
      recordWeightOn(day: DayKey.today(), kg: kg);

  /// Records the weight for [day], replacing any earlier reading for that day.
  ///
  /// One measurement per calendar day: a unique index enforces it, so a second
  /// weigh-in on the same day corrects the first rather than stacking. Editing
  /// an existing day resolves to the same update path, so the entry list and the
  /// add sheet share one write.
  Future<void> recordWeightOn({
    required DayKey day,
    required double kg,
    String? note,
  }) async {
    final existing =
        await (_db.select(_db.weightLog)..where(
              (t) => t.measuredOn.equals(day.value) & t.deletedAt.isNull(),
            ))
            .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.weightLog)..where((t) => t.id.equals(existing.id)))
          .write(WeightLogCompanion(weightKg: Value(kg), note: Value(note)));
      return;
    }

    await _db
        .into(_db.weightLog)
        .insert(
          WeightLogCompanion.insert(
            measuredOn: day.value,
            weightKg: kg,
            note: Value(note),
          ),
        );
  }

  /// Tombstones a weight entry. Rows are never physically removed, so a future
  /// sync can propagate the deletion to other devices.
  Future<void> deleteWeight(String id) async {
    await (_db.update(_db.weightLog)..where((t) => t.id.equals(id))).write(
      WeightLogCompanion(deletedAt: Value(DateTime.now())),
    );
  }

  /// Saves the physical profile, records the weight, and — unless the user has
  /// pinned a manual calorie target — recomputes the target from Mifflin-St
  /// Jeor and stores it as today's target.
  ///
  /// One call rather than three so the profile, the weight log and the target
  /// can never drift out of step: a saved profile always implies a target
  /// computed from exactly those numbers.
  Future<void> saveProfileAndTarget({
    required Sex sex,
    required DateTime birthDate,
    required double heightCm,
    required double weightKg,
    required ActivityLevel activity,
    required WeightGoal goal,
    required double rateKgPerWeek,
  }) async {
    final profile = await _ensureProfile();

    await (_db.update(
      _db.userProfile,
    )..where((t) => t.id.equals(profile.id))).write(
      UserProfileCompanion(
        sex: Value(sex.wire),
        birthDate: Value(birthDate),
        heightCm: Value(heightCm),
        activityLevel: Value(activity.wire),
        goal: Value(goal.wire),
        rateKgPerWeek: Value(rateKgPerWeek),
      ),
    );

    await recordWeight(weightKg);

    final inputs = TdeeInputs(
      sex: sex,
      age: _ageFrom(birthDate),
      heightCm: heightCm,
      weightKg: weightKg,
      activity: activity,
      goal: goal,
      rateKgPerWeek: rateKgPerWeek,
    );

    // Only overwrite the target when it is still auto-managed. Once the user
    // has typed a manual calorie goal, recomputing here would silently discard
    // it — the manual override must win until they clear it.
    final current = await currentTarget();
    if (current != null && !current.isAuto) return;

    final kcal = recommendedCalorieTarget(inputs);
    final macros = defaultMacrosFor(kcal);
    await setTarget(
      kcal: kcal.roundToDouble(),
      proteinG: macros.proteinG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
      isAuto: true,
    );
  }

  /// Whole years since [birthDate], as of today.
  static int _ageFrom(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hadBirthday =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hadBirthday) age -= 1;
    return age;
  }

  // ---------------------------------------------------------------- targets

  /// The target in force on [day]: the most recent one that had taken effect.
  Stream<TargetRow?> watchTargetFor(DayKey day) =>
      (_db.select(_db.targets)
            ..where(
              (t) =>
                  t.effectiveFrom.isSmallerOrEqualValue(day.value) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.effectiveFrom,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(1))
          .watchSingleOrNull();

  /// A one-shot read of today's target.
  ///
  /// A direct query rather than `watchTargetFor(...).first`: subscribing to a
  /// stream just to take its first value keeps a query-stream alive for a
  /// moment for no reason, and — because it resolves only when the stream
  /// emits — deadlocks in a widget test that awaits it before pumping.
  Future<TargetRow?> currentTarget() {
    final today = DayKey.today();
    return (_db.select(_db.targets)
          ..where(
            (t) =>
                t.effectiveFrom.isSmallerOrEqualValue(today.value) &
                t.deletedAt.isNull(),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.effectiveFrom,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Changes today's target, carrying forward anything not passed.
  ///
  /// Edits made on the same day collapse into one row instead of appending a
  /// new one per keystroke — the history that matters is "what did this day's
  /// target end up being", not every intermediate value.
  Future<void> setTarget({
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    int? waterMl,
    bool? isAuto,
  }) async {
    final today = DayKey.today();
    final base = await currentTarget();

    final existingToday =
        await (_db.select(_db.targets)..where(
              (t) => t.effectiveFrom.equals(today.value) & t.deletedAt.isNull(),
            ))
            .getSingleOrNull();

    final companion = TargetsCompanion(
      kcal: Value(kcal ?? base?.kcal ?? defaultKcal),
      proteinG: Value(proteinG ?? base?.proteinG),
      carbsG: Value(carbsG ?? base?.carbsG),
      fatG: Value(fatG ?? base?.fatG),
      waterMl: Value(waterMl ?? base?.waterMl ?? defaultWaterMl),
      isAuto: Value(isAuto ?? false),
    );

    if (existingToday != null) {
      await (_db.update(
        _db.targets,
      )..where((t) => t.id.equals(existingToday.id))).write(companion);
      return;
    }

    await _db
        .into(_db.targets)
        .insert(
          TargetsCompanion.insert(
            effectiveFrom: today.value,
            kcal: companion.kcal.value,
            proteinG: companion.proteinG,
            carbsG: companion.carbsG,
            fatG: companion.fatG,
            waterMl: companion.waterMl,
            isAuto: companion.isAuto,
          ),
        );
  }
}
