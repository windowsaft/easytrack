import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/repositories/off_cache_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late OffCacheRepository repo;

  setUp(() {
    db = UserDatabase.forTesting();
    repo = OffCacheRepository(db);
  });
  tearDown(() => db.close());

  FoodItem cola({double kcal = 42}) => FoodItem(
    ref: const FoodRef(FoodSourceType.offOnline, '5449000000996'),
    name: 'Coca-Cola',
    brand: 'Coca-Cola',
    barcode: '5449000000996',
    nutrients: Nutrients(kcal: kcal, proteinG: 0, carbsG: 10.6, fatG: 0),
    servings: const [ServingOption(label: '1 Portion (250 g)', grams: 250)],
  );

  test('caches a product and reads it back by barcode', () async {
    await repo.cache(cola());
    final item = await repo.byBarcode('5449000000996');
    expect(item, isNotNull);
    expect(item!.name, 'Coca-Cola');
    expect(item.nutrients.carbsG, 10.6);
    expect(item.servings.single.grams, 250);
    expect(item.ref.source, FoodSourceType.offOnline);
  });

  test('a re-cache updates in place rather than duplicating', () async {
    await repo.cache(cola(kcal: 42));
    await repo.cache(cola(kcal: 40));

    final rows = await db.select(db.offCache).get();
    expect(rows, hasLength(1));
    expect((await repo.byBarcode('5449000000996'))!.nutrients.kcal, 40);
  });

  test('an uncached barcode resolves to null', () async {
    expect(await repo.byBarcode('0000000000000'), isNull);
  });
}
