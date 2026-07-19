import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/text/german_normalizer.dart';
import '../db/user_database.dart';
import '../food/food_item.dart';

/// Creates and lists the foods the user owns.
///
/// This is the write side of what [CustomFoodProvider] only reads: the search
/// screen's "Anlegen" and "Schnell-Eintrag" actions create rows here, and its
/// "Favoriten" and "Meine" tabs list them. Kept separate from the diary so that
/// creating a reusable food and logging a portion of it stay distinct steps.
class CustomFoodRepository {
  CustomFoodRepository(this._db);

  final UserDatabase _db;

  /// The user's custom foods, newest first.
  Stream<List<FoodItem>> watchMyFoods() =>
      (_db.select(_db.customFoods)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch()
          .map((rows) => rows.map(_toItem).toList());

  /// Only the ones flagged favourite.
  Stream<List<FoodItem>> watchFavorites() =>
      (_db.select(_db.customFoods)
            ..where((t) => t.deletedAt.isNull() & t.isFavorite.equals(true))
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .watch()
          .map((rows) => rows.map(_toItem).toList());

  /// Creates a food and returns it as a [FoodItem] ready to log.
  ///
  /// [nutrients] are per 100 g. When [servingG] is given it becomes the food's
  /// default portion, which is what a quick calorie entry uses to log an exact
  /// amount without the per-100 g arithmetic surfacing to the user.
  Future<FoodItem> create({
    required String name,
    required Nutrients nutrients,
    double? servingG,
    String? servingLabel,
    bool isFavorite = false,
  }) async {
    final row = await _db
        .into(_db.customFoods)
        .insertReturning(
          CustomFoodsCompanion.insert(
            name: name,
            // Kept in sync with the name here because [CustomFoodProvider]
            // searches this column, not the display name.
            searchText: Value(normalizeGerman(name)),
            kcal: nutrients.kcal,
            proteinG: nutrients.proteinG,
            carbsG: nutrients.carbsG,
            fatG: nutrients.fatG,
            sugarG: Value(nutrients.sugarG),
            fiberG: Value(nutrients.fiberG),
            satFatG: Value(nutrients.satFatG),
            saltG: Value(nutrients.saltG),
            defaultServingG: Value(servingG),
            defaultServingLabel: Value(servingLabel),
            isFavorite: Value(isFavorite),
          ),
        );
    return _toItem(row);
  }

  Future<void> setFavorite(String id, {required bool value}) async {
    await (_db.update(_db.customFoods)..where((t) => t.id.equals(id))).write(
      CustomFoodsCompanion(isFavorite: Value(value)),
    );
  }

  Future<void> delete(String id) async {
    await (_db.update(_db.customFoods)..where((t) => t.id.equals(id))).write(
      CustomFoodsCompanion(deletedAt: Value(DateTime.now())),
    );
  }

  FoodItem _toItem(CustomFood row) => FoodItem(
    ref: FoodRef(FoodSourceType.custom, row.id),
    name: row.name,
    brand: row.brand,
    barcode: row.barcode,
    nutrients: Nutrients(
      kcal: row.kcal,
      proteinG: row.proteinG,
      carbsG: row.carbsG,
      fatG: row.fatG,
      sugarG: row.sugarG,
      fiberG: row.fiberG,
      satFatG: row.satFatG,
      saltG: row.saltG,
    ),
    servings: [
      if (row.defaultServingG != null)
        ServingOption(
          label: row.defaultServingLabel ?? 'Portion',
          grams: row.defaultServingG!,
        ),
    ],
  );
}
