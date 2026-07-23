import 'package:sqlite3/sqlite3.dart';

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/measure_unit.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/text/german_normalizer.dart';
import '../db/reference_database.dart';
import 'food_item.dart';
import 'food_provider.dart';

/// Searches the bundled Bundeslebensmittelschlüssel pack.
///
/// The primary source: 7,140 German foods including 2,050 prepared dishes,
/// always available and always offline.
class BlsProvider implements FoodProvider {
  BlsProvider(this._ref);

  final ReferenceDatabase _ref;

  @override
  FoodSourceType get source => FoodSourceType.bls;

  @override
  double get sourceWeight => 1.0;

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> isAvailable() async => true;

  static const _columns = '''
    f.bls_code, f.name_de, f.food_group, f.search_text,
    f.kcal, f.protein_g, f.carbs_g, f.fat_g,
    f.sugar_g, f.fiber_g, f.sat_fat_g, f.salt_g
  ''';

  @override
  Future<List<FoodSearchResult>> search(String query, {int limit = 30}) async {
    final normalized = normalizeGerman(query);
    if (normalized.isEmpty) return const [];

    final match = buildMatchExpression(normalized);
    if (match == null) return const [];

    final rows = _ref.raw.select(
      '''
      SELECT $_columns, bm25(bls_fts) AS rank
      FROM bls_fts
      JOIN bls_foods f ON f.id = bls_fts.rowid
      WHERE bls_fts MATCH ?
      ORDER BY rank
      LIMIT ?
      ''',
      [match, limit],
    );

    return [for (final row in rows) _toResult(row, normalized)];
  }

  @override
  Future<FoodItem?> byBarcode(String barcode) async => null; // BLS has none

  @override
  Future<FoodItem?> byId(String id) async {
    final rows = _ref.raw.select(
      'SELECT $_columns FROM bls_foods f WHERE f.bls_code = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : _toItem(rows.first);
  }

  FoodSearchResult _toResult(Row row, String normalizedQuery) {
    final searchText = row['search_text'] as String;
    final firstToken = searchText.split(' ').first;

    return FoodSearchResult(
      item: _toItem(row),
      // bm25 returns negative values where lower is better; negate so that
      // higher is better everywhere and providers stay comparable.
      rawScore: -(row['rank'] as double),
      exactMatch: firstToken == normalizedQuery,
      prefixMatch: firstToken.startsWith(normalizedQuery),
    );
  }

  FoodItem _toItem(Row row) {
    double? opt(String column) => row[column] as double?;

    final name = row['name_de'] as String;
    final foodGroup = row['food_group'] as String?;

    return FoodItem(
      ref: FoodRef(FoodSourceType.bls, row['bls_code'] as String),
      name: name,
      foodGroup: foodGroup,
      // BLS has no serving data, so a detected drink just logs in ml.
      measure: detectMeasure(category: foodGroup, name: name),
      nutrients: Nutrients(
        kcal: (row['kcal'] as num).toDouble(),
        // BLS macro coverage is >99%, but the few gaps are genuinely unknown
        // rather than zero. Zero is the only sane display value, and the NULL
        // is preserved in the pack for anything that needs to tell them apart.
        proteinG: opt('protein_g') ?? 0,
        carbsG: opt('carbs_g') ?? 0,
        fatG: opt('fat_g') ?? 0,
        sugarG: opt('sugar_g'),
        fiberG: opt('fiber_g'),
        satFatG: opt('sat_fat_g'),
        saltG: opt('salt_g'),
      ),
    );
  }

  /// Builds an FTS5 MATCH expression from already-normalized query text.
  ///
  /// Every token is quoted, which is what stops FTS5 operators in user input
  /// ("AND", "*", "NOT", a stray quote) from either changing the query's
  /// meaning or throwing a syntax error mid-keystroke.
  ///
  /// All tokens are required. The last one gets a prefix wildcard so that
  /// results appear while the user is still typing it.
  static String? buildMatchExpression(String normalizedQuery) {
    final tokens = normalizedQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    final parts = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final quoted = '"${tokens[i]}"';
      // Only the final token is a prefix; earlier ones the user finished typing.
      parts.add(i == tokens.length - 1 ? '$quoted*' : quoted);
    }
    return parts.join(' AND ');
  }
}
