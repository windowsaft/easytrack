import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late SettingsRepository repository;

  setUp(() {
    db = UserDatabase.forTesting();
    repository = SettingsRepository(db);
  });
  tearDown(() => db.close());

  const today = DayKey(20260720);
  const yesterday = DayKey(20260719);

  test('records a weight and reads it back as the latest', () async {
    await repository.recordWeightOn(day: today, kg: 79.4);
    expect(await repository.watchLatestWeightKg().first, 79.4);
  });

  test('a second reading on the same day corrects the first', () async {
    await repository.recordWeightOn(day: today, kg: 80);
    await repository.recordWeightOn(day: today, kg: 79.2);

    final log = await repository.watchWeightLog().first;
    expect(log, hasLength(1));
    expect(log.single.weightKg, 79.2);
  });

  test('keeps a separate entry per day, oldest first', () async {
    await repository.recordWeightOn(day: today, kg: 79);
    await repository.recordWeightOn(day: yesterday, kg: 80);

    final log = await repository.watchWeightLog().first;
    expect(log.map((e) => e.measuredOn), [yesterday.value, today.value]);
    // The most recent calendar day wins the "latest" read, not the last write.
    expect(await repository.watchLatestWeightKg().first, 79);
  });

  test('recordWeight targets today', () async {
    await repository.recordWeight(77.7);
    final log = await repository.watchWeightLog().first;
    expect(log.single.measuredOn, DayKey.today().value);
  });

  test('deleting tombstones the entry but keeps the row', () async {
    await repository.recordWeightOn(day: today, kg: 79);
    final entry = (await repository.watchWeightLog().first).single;

    await repository.deleteWeight(entry.id);

    expect(await repository.watchWeightLog().first, isEmpty);
    expect(await repository.watchLatestWeightKg().first, isNull);
    // Row still present as a tombstone.
    expect(await db.select(db.weightLog).get(), hasLength(1));
  });

  test('a new reading can reuse a tombstoned day', () async {
    await repository.recordWeightOn(day: today, kg: 79);
    final entry = (await repository.watchWeightLog().first).single;
    await repository.deleteWeight(entry.id);

    // The partial unique index excludes tombstones, so this must not conflict.
    await repository.recordWeightOn(day: today, kg: 81);

    final log = await repository.watchWeightLog().first;
    expect(log, hasLength(1));
    expect(log.single.weightKg, 81);
  });
}
