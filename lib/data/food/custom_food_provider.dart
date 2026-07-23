import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/measure_unit.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/text/german_normalizer.dart';
import '../db/user_database.dart';
import 'food_item.dart';
import 'food_provider.dart';

/// Searches the foods the user created themselves.
///
/// No FTS index here: this table holds tens of rows, not hundreds of thousands,
/// so a substring scan is both faster in practice and more forgiving — it
/// matches mid-word, which FTS5 prefix matching cannot do.
class CustomFoodProvider implements FoodProvider {
  CustomFoodProvider(this._db);

  final UserDatabase _db;

  @override
  FoodSourceType get source => FoodSourceType.custom;

  /// Above every other source: the user typed these in, so when they match they
  /// are almost certainly what was meant.
  @override
  double get sourceWeight => 1.1;

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<FoodSearchResult>> search(String query, {int limit = 30}) async {
    final normalized = normalizeGerman(query);
    if (normalized.isEmpty) return const [];

    final rows =
        await (_db.select(_db.customFoods)
              ..where(
                (t) =>
                    t.deletedAt.isNull() & t.searchText.like('%$normalized%'),
              )
              ..limit(limit))
            .get();

    return [
      for (final row in rows)
        FoodSearchResult(
          item: _toItem(row),
          // Rank by how early the match starts: a name beginning with the query
          // is a better hit than one mentioning it at the end.
          rawScore: 1.0 / (1 + row.searchText.indexOf(normalized)),
          exactMatch: row.searchText == normalized,
          prefixMatch: row.searchText.startsWith(normalized),
        ),
    ];
  }

  @override
  Future<FoodItem?> byBarcode(String barcode) async {
    final row =
        await (_db.select(_db.customFoods)
              ..where((t) => t.deletedAt.isNull() & t.barcode.equals(barcode))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toItem(row);
  }

  @override
  Future<FoodItem?> byId(String id) async {
    final row =
        await (_db.select(_db.customFoods)
              ..where((t) => t.deletedAt.isNull() & t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toItem(row);
  }

  FoodItem _toItem(CustomFood row) {
    final measure = MeasureUnit.fromWire(row.unit);
    return FoodItem(
      ref: FoodRef(FoodSourceType.custom, row.id),
      name: row.name,
      brand: row.brand,
      barcode: row.barcode,
      measure: measure,
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
            unit: row.defaultServingLabel ?? 'Portion',
            grams: row.defaultServingG!,
            measure: measure,
          ),
      ],
    );
  }
}
