import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:easytrack/domain/tdee.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = UserDatabase.forTesting();
    repo = SettingsRepository(db);
  });
  tearDown(() => db.close());

  /// A birth date that is exactly [age] years before today, so the computed age
  /// is stable regardless of when the test runs.
  DateTime birthdayFor(int age) {
    final now = DateTime.now();
    return DateTime(now.year - age, now.month, now.day);
  }

  Future<void> saveMaintain({double weight = 80}) => repo.saveProfileAndTarget(
    sex: Sex.male,
    birthDate: birthdayFor(30),
    heightCm: 180,
    weightKg: weight,
    activity: ActivityLevel.moderate,
    goal: WeightGoal.maintain,
    rateKgPerWeek: 0,
  );

  group('saveProfileAndTarget', () {
    test('writes a computed, auto-managed target', () async {
      await saveMaintain();

      final target = await repo.currentTarget();
      // BMR 1780 * 1.55 = 2759, maintenance.
      expect(target, isNotNull);
      expect(target!.kcal, closeTo(2759, 0.5));
      expect(target.isAuto, isTrue);
      // Macros come from the 40/30/30 default split.
      expect(target.carbsG, closeTo(2759 * 0.40 / 4, 0.5));
    });

    test('records the weight in the weight log', () async {
      await saveMaintain(weight: 82.5);
      expect(await repo.watchLatestWeightKg().first, 82.5);
    });

    test(
      'a second save on the same day corrects the weight, not stacks it',
      () async {
        await saveMaintain(weight: 80);
        await saveMaintain(weight: 79);
        expect(await repo.watchLatestWeightKg().first, 79);
      },
    );

    test('recomputes over a manual target when the calculator is run', () async {
      // User computes a target, then types their own.
      await saveMaintain();
      await repo.setTarget(kcal: 1800); // manual: isAuto defaults false

      final manual = await repo.currentTarget();
      expect(manual!.isAuto, isFalse);
      expect(manual.kcal, 1800);

      // Re-running the calculator is an explicit "neu berechnen": the computed
      // value must win over the stale manual override and become auto again.
      await saveMaintain();
      final after = await repo.currentTarget();
      expect(after!.kcal, closeTo(2759, 0.5));
      expect(after.isAuto, isTrue);
    });

    test('a loss goal lands below maintenance', () async {
      await repo.saveProfileAndTarget(
        sex: Sex.male,
        birthDate: birthdayFor(30),
        heightCm: 180,
        weightKg: 80,
        activity: ActivityLevel.moderate,
        goal: WeightGoal.lose,
        rateKgPerWeek: 0.5,
      );
      final target = await repo.currentTarget();
      // 2759 - 550 = 2209.
      expect(target!.kcal, closeTo(2209, 0.5));
    });
  });
}
