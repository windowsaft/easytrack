import 'package:drift/drift.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/measure_unit.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/text/german_normalizer.dart';
import '../db/user_database.dart';
import '../food/food_item.dart';

/// Persists Open Food Facts products fetched online, keyed by barcode.
///
/// Lives in the **user** database, not the reference pack, on purpose: a product
/// the user scanned must survive the pack being replaced wholesale, and by
/// construction the cache holds newer data than any shipped pack — which is why
/// the barcode chain consults it before the local pack.
class OffCacheRepository {
  OffCacheRepository(this._db);

  final UserDatabase _db;

  Future<FoodItem?> byBarcode(String barcode) async {
    final row =
        await (_db.select(_db.offCache)
              ..where((t) => t.barcode.equals(barcode) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toItem(row);
  }

  /// Upserts [item] into the cache, preserving the row id on refresh so a later
  /// sync sees an update rather than a delete-and-recreate.
  Future<void> cache(FoodItem item) async {
    final barcode = item.barcode ?? item.ref.id;
    final serving = item.servings.isEmpty ? null : item.servings.first.grams;
    final n = item.nutrients;

    final existing =
        await (_db.select(_db.offCache)
              ..where((t) => t.barcode.equals(barcode) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();

    final companion = OffCacheCompanion(
      name: Value(item.name),
      brand: Value(item.brand),
      searchText: Value(
        normalizeGerman([item.name, item.brand ?? ''].join(' ')),
      ),
      servingSizeG: Value(serving),
      kcal: Value(n.kcal),
      proteinG: Value(n.proteinG),
      carbsG: Value(n.carbsG),
      fatG: Value(n.fatG),
      sugarG: Value(n.sugarG),
      fiberG: Value(n.fiberG),
      satFatG: Value(n.satFatG),
      saltG: Value(n.saltG),
      unit: Value(item.measure.wire),
      fetchedAt: Value(DateTime.now()),
    );

    if (existing != null) {
      await (_db.update(
        _db.offCache,
      )..where((t) => t.id.equals(existing.id))).write(companion);
      return;
    }

    await _db
        .into(_db.offCache)
        .insert(
          OffCacheCompanion.insert(
            barcode: barcode,
            name: item.name,
            brand: Value(item.brand),
            searchText: companion.searchText,
            servingSizeG: Value(serving),
            kcal: n.kcal,
            proteinG: n.proteinG,
            carbsG: n.carbsG,
            fatG: n.fatG,
            sugarG: Value(n.sugarG),
            fiberG: Value(n.fiberG),
            satFatG: Value(n.satFatG),
            saltG: Value(n.saltG),
            unit: Value(item.measure.wire),
          ),
        );
  }

  FoodItem _toItem(CachedProduct row) {
    final measure = MeasureUnit.fromWire(row.unit);
    return FoodItem(
      // Labelled offOnline: it is Open Food Facts data, just persisted. The
      // display label is the same either way, and the diary snapshots nutrients
      // regardless of source.
      ref: FoodRef(FoodSourceType.offOnline, row.barcode),
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
        if (row.servingSizeG != null && row.servingSizeG! > 0)
          ServingOption(
            unit: 'Portion',
            grams: row.servingSizeG!,
            measure: measure,
          ),
      ],
    );
  }
}
