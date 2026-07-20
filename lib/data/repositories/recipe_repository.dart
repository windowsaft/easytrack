import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/text/german_normalizer.dart';
import '../../domain/recipe.dart';
import '../db/user_database.dart';
import '../food/food_item.dart';
import 'diary_repository.dart' show Rx;

/// A recipe together with its ingredients and the scaling computed from them.
///
/// The UI works with drift's [Recipe]/[RecipeIngredient] rows directly, the way
/// the diary works with [DiaryEntry]; this just bundles them with the derived
/// [RecipeScaling] so a screen never recomputes it by hand.
class RecipeDetail {
  RecipeDetail({required this.recipe, required this.ingredients})
    : components = [for (final i in ingredients) _componentOf(i)],
      scaling = RecipeScaling.of(
        ingredients.map(_componentOf),
        cookedWeightG: recipe.cookedWeightG,
      );

  final Recipe recipe;
  final List<RecipeIngredient> ingredients;
  final List<RecipeComponent> components;
  final RecipeScaling scaling;

  /// The recipe as a loggable food.
  ///
  /// Its nutrients are per 100 g of the finished dish, so it flows through the
  /// exact same portion picker and diary snapshot path as any other food. The
  /// yield weight is offered as a named "whole batch" serving; the picker's
  /// grams fallback covers weighing an actual plate.
  FoodItem toFoodItem() => FoodItem(
    ref: FoodRef(FoodSourceType.recipe, recipe.id),
    name: recipe.name,
    nutrients: scaling.per100g,
    servings: [
      if (scaling.yieldWeightG > 0)
        ServingOption(
          label: 'Ganze Menge (${scaling.yieldWeightG.round()} g)',
          grams: scaling.yieldWeightG,
        ),
    ],
  );

  static RecipeComponent _componentOf(RecipeIngredient i) => RecipeComponent(
    ref: FoodRef(FoodSourceType.fromWire(i.sourceType), i.sourceId),
    name: i.nameSnapshot,
    amountG: i.amountG,
    nutrients: Nutrients(
      kcal: i.kcal,
      proteinG: i.proteinG,
      carbsG: i.carbsG,
      fatG: i.fatG,
      sugarG: i.sugarG,
      fiberG: i.fiberG,
      satFatG: i.satFatG,
      saltG: i.saltG,
    ),
  );
}

/// Creates, lists and resolves the user's recipes.
///
/// The write side of what [RecipeProvider] reads for search. Kept separate from
/// the diary so building a reusable recipe and logging a portion of it stay
/// distinct steps, mirroring [CustomFoodRepository].
class RecipeRepository {
  RecipeRepository(this._db);

  final UserDatabase _db;

  /// Every recipe with its ingredients, newest first.
  Stream<List<RecipeDetail>> watchRecipes() {
    final recipes =
        (_db.select(_db.recipes)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .watch();

    final ingredients =
        (_db.select(_db.recipeIngredients)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
            .watch();

    return Rx.combineLatest([recipes, ingredients], (values) {
      final recipeRows = values[0]! as List<Recipe>;
      final ingredientRows = values[1]! as List<RecipeIngredient>;

      final byRecipe = <String, List<RecipeIngredient>>{};
      for (final ing in ingredientRows) {
        (byRecipe[ing.recipeId] ??= []).add(ing);
      }

      return [
        for (final recipe in recipeRows)
          RecipeDetail(
            recipe: recipe,
            ingredients: byRecipe[recipe.id] ?? const [],
          ),
      ];
    });
  }

  /// One recipe, or null if it was never created or has been deleted.
  ///
  /// A direct read rather than a stream `.first`, so callers (the provider's
  /// `byId`, the editor's prefill) can await it before any UI has pumped.
  Future<RecipeDetail?> getRecipe(String id) async {
    final recipe = await (_db.select(
      _db.recipes,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (recipe == null) return null;

    final ingredients =
        await (_db.select(_db.recipeIngredients)
              ..where((t) => t.recipeId.equals(id) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
            .get();

    return RecipeDetail(recipe: recipe, ingredients: ingredients);
  }

  /// Creates a recipe and its ingredients atomically, returning the new id.
  Future<String> createRecipe({
    required String name,
    required List<RecipeComponent> components,
    String? notes,
    double? cookedWeightG,
    bool isFavorite = false,
  }) {
    return _db.transaction(() async {
      final recipe = await _db
          .into(_db.recipes)
          .insertReturning(
            RecipesCompanion.insert(
              name: name,
              // Kept in sync with the name here because [RecipeProvider]
              // searches this column, not the display name.
              searchText: Value(normalizeGerman(name)),
              notes: Value(notes),
              cookedWeightG: Value(cookedWeightG),
              isFavorite: Value(isFavorite),
            ),
          );
      await _insertComponents(recipe.id, components);
      return recipe.id;
    });
  }

  /// Rewrites a recipe and its ingredient set.
  ///
  /// The ingredient rows are replaced wholesale: the old ones are tombstoned and
  /// the new set inserted. That honours the never-hard-delete rule the sync
  /// layer will depend on, and is simpler than diffing when the editor already
  /// works on a plain in-memory list.
  Future<void> updateRecipe({
    required String id,
    required String name,
    required List<RecipeComponent> components,
    String? notes,
    double? cookedWeightG,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.recipes)..where((t) => t.id.equals(id))).write(
        RecipesCompanion(
          name: Value(name),
          searchText: Value(normalizeGerman(name)),
          notes: Value(notes),
          cookedWeightG: Value(cookedWeightG),
        ),
      );

      await (_db.update(_db.recipeIngredients)
            ..where((t) => t.recipeId.equals(id) & t.deletedAt.isNull()))
          .write(RecipeIngredientsCompanion(deletedAt: Value(DateTime.now())));

      await _insertComponents(id, components);
    });
  }

  Future<void> setFavorite(String id, {required bool value}) async {
    await (_db.update(_db.recipes)..where((t) => t.id.equals(id))).write(
      RecipesCompanion(isFavorite: Value(value)),
    );
  }

  /// Tombstones a recipe and its ingredients. Rows are never physically removed,
  /// so a future sync can propagate the deletion to other devices.
  Future<void> deleteRecipe(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.recipes)..where((t) => t.id.equals(id))).write(
        RecipesCompanion(deletedAt: Value(DateTime.now())),
      );
      await (_db.update(_db.recipeIngredients)
            ..where((t) => t.recipeId.equals(id) & t.deletedAt.isNull()))
          .write(RecipeIngredientsCompanion(deletedAt: Value(DateTime.now())));
    });
  }

  Future<void> _insertComponents(
    String recipeId,
    List<RecipeComponent> components,
  ) async {
    await _db.batch((batch) {
      for (var i = 0; i < components.length; i++) {
        final c = components[i];
        batch.insert(
          _db.recipeIngredients,
          RecipeIngredientsCompanion.insert(
            recipeId: recipeId,
            sourceType: c.ref.source.wireName,
            sourceId: c.ref.id,
            nameSnapshot: c.name,
            amountG: c.amountG,
            sortOrder: Value(i),
            kcal: c.nutrients.kcal,
            proteinG: c.nutrients.proteinG,
            carbsG: c.nutrients.carbsG,
            fatG: c.nutrients.fatG,
            sugarG: Value(c.nutrients.sugarG),
            fiberG: Value(c.nutrients.fiberG),
            satFatG: Value(c.nutrients.satFatG),
            saltG: Value(c.nutrients.saltG),
          ),
        );
      }
    });
  }
}
