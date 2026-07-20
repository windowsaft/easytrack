import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/text/german_normalizer.dart';
import '../db/user_database.dart';
import '../repositories/recipe_repository.dart';
import 'food_item.dart';
import 'food_provider.dart';

/// Makes the user's recipes searchable and loggable like any other food.
///
/// Like [CustomFoodProvider] this is a substring scan, not FTS: a personal
/// recipe book is tens of rows, and a scan matches mid-word where FTS5 prefix
/// matching cannot.
class RecipeProvider implements FoodProvider {
  RecipeProvider(this._db);

  final UserDatabase _db;

  @override
  FoodSourceType get source => FoodSourceType.recipe;

  /// Just below custom foods and above the reference sources: a recipe is the
  /// user's own, but a name match on it is a shade less specific than a match on
  /// a food they entered as a single item.
  @override
  double get sourceWeight => 1.05;

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<FoodSearchResult>> search(String query, {int limit = 30}) async {
    final normalized = normalizeGerman(query);
    if (normalized.isEmpty) return const [];

    final recipes =
        await (_db.select(_db.recipes)
              ..where(
                (t) =>
                    t.deletedAt.isNull() & t.searchText.like('%$normalized%'),
              )
              ..limit(limit))
            .get();
    if (recipes.isEmpty) return const [];

    // Fetch the ingredients of every matched recipe in one query, then group,
    // rather than a round-trip per hit.
    final ids = [for (final r in recipes) r.id];
    final ingredients = await (_db.select(
      _db.recipeIngredients,
    )..where((t) => t.deletedAt.isNull() & t.recipeId.isIn(ids))).get();

    final byRecipe = <String, List<RecipeIngredient>>{};
    for (final ing in ingredients) {
      (byRecipe[ing.recipeId] ??= []).add(ing);
    }

    return [
      for (final recipe in recipes)
        FoodSearchResult(
          item: RecipeDetail(
            recipe: recipe,
            ingredients: byRecipe[recipe.id] ?? const [],
          ).toFoodItem(),
          // Rank by how early the match starts, matching CustomFoodProvider.
          rawScore: 1.0 / (1 + recipe.searchText.indexOf(normalized)),
          exactMatch: recipe.searchText == normalized,
          prefixMatch: recipe.searchText.startsWith(normalized),
        ),
    ];
  }

  @override
  Future<FoodItem?> byBarcode(String barcode) async => null;

  @override
  Future<FoodItem?> byId(String id) async {
    final detail = await RecipeRepository(_db).getRecipe(id);
    return detail?.toFoodItem();
  }
}
