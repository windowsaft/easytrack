import 'package:drift/drift.dart';

import '../../core/time/day_key.dart';
import '../../domain/history.dart';
import '../db/user_database.dart';
import 'diary_repository.dart' show Rx;
import 'settings_repository.dart';

/// Rolls the diary up per day over a date range, for the Verlauf analytics.
///
/// Aggregation is done in SQL (one grouped query per table) and combined
/// reactively, so the charts follow live edits the way the diary does. Days with
/// no entries are still emitted, as zero-intake days, so a range renders as a
/// continuous run rather than a sparse one.
class HistoryRepository {
  HistoryRepository(this._db);

  final UserDatabase _db;

  Stream<List<DayHistory>> watchRange(DayKey from, DayKey to) {
    final vars = [Variable.withInt(from.value), Variable.withInt(to.value)];

    final diary = _db
        .customSelect(
          'SELECT logged_on AS d, SUM(kcal) AS kcal, SUM(carbs_g) AS carbs, '
          'SUM(protein_g) AS protein, SUM(fat_g) AS fat FROM diary_entries '
          'WHERE deleted_at IS NULL AND logged_on BETWEEN ?1 AND ?2 '
          'GROUP BY logged_on',
          variables: vars,
          readsFrom: {_db.diaryEntries},
        )
        .watch();

    final water = _db
        .customSelect(
          'SELECT logged_on AS d, SUM(amount_ml) AS ml FROM water_log '
          'WHERE deleted_at IS NULL AND logged_on BETWEEN ?1 AND ?2 '
          'GROUP BY logged_on',
          variables: vars,
          readsFrom: {_db.waterLog},
        )
        .watch();

    final activity = _db
        .customSelect(
          'SELECT logged_on AS d, SUM(kcal_burned_raw * safety_factor) AS kcal '
          'FROM activity_entries WHERE deleted_at IS NULL '
          'AND logged_on BETWEEN ?1 AND ?2 GROUP BY logged_on',
          variables: vars,
          readsFrom: {_db.activityEntries},
        )
        .watch();

    final targets =
        (_db.select(_db.targets)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.effectiveFrom.isSmallerOrEqualValue(to.value),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.effectiveFrom)]))
            .watch();

    // The activity-adds-to-budget toggle is profile state (not history-
    // preserving), so the current value applies to every day in the range.
    final profile =
        (_db.select(_db.userProfile)
              ..where((t) => t.deletedAt.isNull())
              ..limit(1))
            .watchSingleOrNull();

    return Rx.combineLatest([diary, water, activity, targets, profile], (
      values,
    ) {
      final diaryRows = values[0]! as List<QueryRow>;
      final waterRows = values[1]! as List<QueryRow>;
      final activityRows = values[2]! as List<QueryRow>;
      final targetRows = values[3]! as List<TargetRow>;
      final activityAdds =
          (values[4] as UserProfileRow?)?.activityAddsToBudget ?? true;

      final byDay = {for (final r in diaryRows) r.read<int>('d'): r};
      final waterByDay = {
        for (final r in waterRows) r.read<int>('d'): r.read<int?>('ml') ?? 0,
      };
      final activityByDay = {
        for (final r in activityRows)
          r.read<int>('d'): r.read<double?>('kcal') ?? 0.0,
      };

      // targetRows are ascending by effectiveFrom, so the last one that has
      // taken effect on or before a day is that day's target.
      double targetFor(int day) {
        var kcal = SettingsRepository.defaultKcal;
        for (final t in targetRows) {
          if (t.effectiveFrom <= day) {
            kcal = t.kcal;
          } else {
            break;
          }
        }
        return kcal;
      }

      final out = <DayHistory>[];
      for (var day = from; day.value <= to.value; day = day.next) {
        final row = byDay[day.value];
        out.add(
          DayHistory(
            day: day,
            kcal: row?.read<double?>('kcal') ?? 0,
            carbsG: row?.read<double?>('carbs') ?? 0,
            proteinG: row?.read<double?>('protein') ?? 0,
            fatG: row?.read<double?>('fat') ?? 0,
            waterMl: waterByDay[day.value] ?? 0,
            activityKcal: activityByDay[day.value] ?? 0,
            targetKcal: targetFor(day.value),
            activityAddsToBudget: activityAdds,
          ),
        );
      }
      return out;
    });
  }
}
