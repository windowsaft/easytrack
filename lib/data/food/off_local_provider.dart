import 'package:sqlite3/sqlite3.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/text/german_normalizer.dart';
import '../pack/off_pack_database.dart';
import 'bls_provider.dart' show BlsProvider;
import 'food_item.dart';
import 'food_provider.dart';

/// Searches the downloaded Open Food Facts product pack.
///
/// The branded/barcoded counterpart to [BlsProvider]: same FTS5 machinery over
/// the same normalized German search text, so a query folds identically in both.
/// Only present in the orchestrator once a pack has actually been installed.
class OffLocalProvider implements FoodProvider {
  OffLocalProvider(this._pack);

  final OffPackDatabase _pack;

  @override
  FoodSourceType get source => FoodSourceType.offLocal;

  /// Below BLS: BLS entries are lab-grade generics that match how people log
  /// home-cooked food, whereas a branded product is better reached by barcode
  /// than by typing its name. Both still show, with a source badge.
  @override
  double get sourceWeight => 0.85;

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => true;

  static const _columns = '''
    f.barcode, f.name, f.brands, f.search_text, f.serving_size_g,
    f.kcal, f.protein_g, f.carbs_g, f.fat_g,
    f.sugar_g, f.sat_fat_g, f.salt_g, f.fiber_g
  ''';

  @override
  Future<List<FoodSearchResult>> search(String query, {int limit = 30}) async {
    final normalized = normalizeGerman(query);
    if (normalized.isEmpty) return const [];

    // The same quoting/prefix rules as BLS, so operator characters in a
    // half-typed query can never change the query's meaning or throw.
    final match = BlsProvider.buildMatchExpression(normalized);
    if (match == null) return const [];

    final rows = _pack.raw.select(
      '''
      SELECT $_columns, bm25(off_fts) AS rank
      FROM off_fts
      JOIN off_foods f ON f.id = off_fts.rowid
      WHERE off_fts MATCH ?
      ORDER BY rank
      LIMIT ?
      ''',
      [match, limit],
    );

    return [for (final row in rows) _toResult(row, normalized)];
  }

  @override
  Future<FoodItem?> byBarcode(String barcode) async {
    final rows = _pack.raw.select(
      'SELECT $_columns FROM off_foods f WHERE f.barcode = ? LIMIT 1',
      [barcode],
    );
    return rows.isEmpty ? null : _toItem(rows.first);
  }

  /// For OFF the source id *is* the barcode, so id resolution is barcode lookup.
  @override
  Future<FoodItem?> byId(String id) => byBarcode(id);

  FoodSearchResult _toResult(Row row, String normalizedQuery) {
    final searchText = row['search_text'] as String;
    final firstToken = searchText.split(' ').first;

    return FoodSearchResult(
      item: _toItem(row),
      // bm25 is negative-lower-is-better; negate so higher is better and
      // providers stay comparable when the orchestrator merges them.
      rawScore: -(row['rank'] as double),
      exactMatch: firstToken == normalizedQuery,
      prefixMatch: firstToken.startsWith(normalizedQuery),
    );
  }

  FoodItem _toItem(Row row) {
    double? opt(String column) => (row[column] as num?)?.toDouble();
    final serving = opt('serving_size_g');
    final brands = row['brands'] as String?;

    return FoodItem(
      ref: FoodRef(FoodSourceType.offLocal, row['barcode'] as String),
      name: row['name'] as String,
      brand: brands != null && brands.isNotEmpty ? brands : null,
      barcode: row['barcode'] as String,
      nutrients: Nutrients(
        kcal: (row['kcal'] as num).toDouble(),
        proteinG: opt('protein_g') ?? 0,
        carbsG: opt('carbs_g') ?? 0,
        fatG: opt('fat_g') ?? 0,
        sugarG: opt('sugar_g'),
        fiberG: opt('fiber_g'),
        satFatG: opt('sat_fat_g'),
        saltG: opt('salt_g'),
      ),
      servings: [
        // A branded product usually declares a serving; offer it, still with the
        // 100 g fallback the picker always adds.
        if (serving != null && serving > 0)
          ServingOption(
            label: '1 Portion (${_trimGrams(serving)} g)',
            grams: serving,
          ),
      ],
    );
  }

  static String _trimGrams(double g) =>
      g == g.roundToDouble() ? g.round().toString() : g.toStringAsFixed(1);
}
