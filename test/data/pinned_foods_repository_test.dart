import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/repositories/pinned_foods_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late PinnedFoodsRepository repo;

  setUp(() {
    db = UserDatabase.forTesting();
    repo = PinnedFoodsRepository(db);
  });
  tearDown(() => db.close());

  FoodItem bls(String code, String name) => FoodItem(
    ref: FoodRef(FoodSourceType.bls, code),
    name: name,
    nutrients: Nutrients.zero,
  );

  test('pins a food and reports it pinned', () async {
    final food = bls('B1', 'Vollkornbrot');
    expect(await repo.isPinned(food.ref), isFalse);

    await repo.pin(food);

    expect(await repo.isPinned(food.ref), isTrue);
    final pins = await repo.watchPinned().first;
    expect(pins.map((p) => p.nameSnapshot), ['Vollkornbrot']);
    expect(pins.single.sourceType, FoodSourceType.bls.wireName);
  });

  test('toggle pins then unpins', () async {
    final food = bls('B1', 'Käse');
    await repo.toggle(food);
    expect(await repo.isPinned(food.ref), isTrue);
    await repo.toggle(food);
    expect(await repo.isPinned(food.ref), isFalse);
    expect(await repo.watchPinned().first, isEmpty);
  });

  test('unpin tombstones the row rather than deleting it', () async {
    final food = bls('B1', 'Milch');
    await repo.pin(food);
    await repo.unpin(food.ref);

    expect(await repo.watchPinned().first, isEmpty);
    // The tombstone survives for a future sync.
    expect(await db.select(db.pinnedFoods).get(), hasLength(1));
  });

  test('re-pinning revives the row without a unique-index conflict', () async {
    final food = bls('B1', 'Apfel');
    await repo.pin(food);
    await repo.unpin(food.ref);

    // The (source_type, source_id) unique index covers the tombstone, so a
    // fresh insert would conflict — pin must revive instead.
    await repo.pin(food);

    expect(await repo.isPinned(food.ref), isTrue);
    expect(await db.select(db.pinnedFoods).get(), hasLength(1));
  });
}
