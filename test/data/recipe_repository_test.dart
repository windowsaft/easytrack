import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/recipe_provider.dart';
import 'package:easytrack/data/repositories/diary_repository.dart';
import 'package:easytrack/data/repositories/recipe_repository.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:easytrack/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeComponent component(
  String name,
  double amountG, {
  required double kcal,
  double protein = 0,
  double carbs = 0,
  double fat = 0,
}) => RecipeComponent(
  ref: FoodRef(FoodSourceType.bls, name),
  name: name,
  amountG: amountG,
  nutrients: Nutrients(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat),
);

void main() {
  late UserDatabase db;
  late RecipeRepository repository;

  final chili = [
    component('Hackfleisch', 500, kcal: 1050, protein: 100, fat: 75),
    component('Kidneybohnen', 400, kcal: 380, protein: 26, carbs: 60, fat: 2),
    component(
      'Tomaten passiert',
      500,
      kcal: 175,
      protein: 8,
      carbs: 35,
      fat: 1,
    ),
  ];

  setUp(() {
    db = UserDatabase.forTesting();
    repository = RecipeRepository(db);
  });
  tearDown(() => db.close());

  group('creating', () {
    test('stores the recipe with its ingredients', () async {
      final id = await repository.createRecipe(
        name: 'Chili con Carne',
        components: chili,
      );

      final detail = await repository.getRecipe(id);
      expect(detail, isNotNull);
      expect(detail!.recipe.name, 'Chili con Carne');
      expect(detail.ingredients, hasLength(3));
      expect(detail.scaling.batchNutrients.kcal, closeTo(1605, 0.01));
      // Ingredient order is preserved by sort_order.
      expect(
        detail.ingredients.map((i) => i.nameSnapshot).first,
        'Hackfleisch',
      );
    });

    test('a cooked weight overrides the yield used for scaling', () async {
      final id = await repository.createRecipe(
        name: 'Eingekochtes',
        components: chili,
        cookedWeightG: 1100,
      );

      final detail = await repository.getRecipe(id);
      expect(detail!.scaling.yieldWeightG, 1100);
      expect(detail.scaling.per100g.kcal, closeTo(145.91, 0.01));
    });

    test('exposes the recipe as a per-100 g loggable food', () async {
      final id = await repository.createRecipe(
        name: 'Chili',
        components: chili,
      );
      final food = (await repository.getRecipe(id))!.toFoodItem();

      expect(food.ref.source, FoodSourceType.recipe);
      expect(food.ref.id, id);
      expect(food.nutrients.kcal, closeTo(114.64, 0.01));
      // A portion of the whole batch is offered as a named serving.
      expect(food.servings.single.grams, 1400);
    });

    test('the search stream emits the new recipe', () async {
      await repository.createRecipe(name: 'Chili', components: chili);
      final list = await repository.watchRecipes().first;
      expect(list, hasLength(1));
      expect(list.single.recipe.name, 'Chili');
    });
  });

  group('editing', () {
    test('replaces the ingredient set, tombstoning the old rows', () async {
      final id = await repository.createRecipe(
        name: 'Chili',
        components: chili,
      );

      await repository.updateRecipe(
        id: id,
        name: 'Chili (leichter)',
        components: [component('Tofu', 300, kcal: 240, protein: 24)],
      );

      final detail = await repository.getRecipe(id);
      expect(detail!.recipe.name, 'Chili (leichter)');
      expect(detail.ingredients, hasLength(1));
      expect(detail.ingredients.single.nameSnapshot, 'Tofu');

      // The old rows survive as tombstones for a future sync.
      final allRows = await db.select(db.recipeIngredients).get();
      expect(allRows, hasLength(4));
      expect(allRows.where((r) => r.deletedAt == null), hasLength(1));
    });

    test('toggles the favourite flag', () async {
      final id = await repository.createRecipe(
        name: 'Chili',
        components: chili,
      );
      await repository.setFavorite(id, value: true);
      expect((await repository.getRecipe(id))!.recipe.isFavorite, isTrue);
    });
  });

  group('deleting', () {
    test('tombstones the recipe but keeps the rows', () async {
      final id = await repository.createRecipe(
        name: 'Chili',
        components: chili,
      );
      await repository.deleteRecipe(id);

      expect(await repository.getRecipe(id), isNull);
      expect(await repository.watchRecipes().first, isEmpty);
      // Row still present, just tombstoned.
      expect(await db.select(db.recipes).get(), hasLength(1));
    });
  });

  group('RecipeProvider search', () {
    test('finds a recipe by German-normalized text', () async {
      await repository.createRecipe(
        name: 'Käsespätzle',
        components: [component('Käse', 100, kcal: 350)],
      );

      final provider = RecipeProvider(db);
      final hits = await provider.search('kaese');
      expect(hits, hasLength(1));
      expect(hits.single.item.name, 'Käsespätzle');
    });

    test('byId resolves to the loggable food', () async {
      final id = await repository.createRecipe(
        name: 'Chili',
        components: chili,
      );
      final food = await RecipeProvider(db).byId(id);
      expect(food, isNotNull);
      expect(food!.nutrients.kcal, closeTo(114.64, 0.01));
    });

    test('byBarcode never matches a recipe', () async {
      expect(await RecipeProvider(db).byBarcode('12345'), isNull);
    });
  });

  group('logging a recipe portion', () {
    test('snapshots scaled nutrients into the diary', () async {
      // The plan's acceptance test 5: build a recipe, log a portion weight.
      final id = await repository.createRecipe(
        name: 'Chili',
        components: chili,
      );
      final food = (await repository.getRecipe(id))!.toFoodItem();

      const day = DayKey(20260720);
      final diary = DiaryRepository(db, SettingsRepository(db));
      await diary.addEntry(
        day: day,
        meal: MealType.dinner,
        food: food,
        amountG: 450,
      );

      final summary = await diary.watchDay(day).first;
      // 1605 kcal batch, 450 g of 1400 g.
      expect(summary.consumed.kcal, closeTo(515.89, 0.5));

      // Stored as a snapshot, not a live reference to the recipe.
      final entry = (await db.select(db.diaryEntries).get()).single;
      expect(entry.sourceType, FoodSourceType.recipe.wireName);
      expect(entry.sourceId, id);
      expect(entry.nameSnapshot, 'Chili');
    });
  });
}
