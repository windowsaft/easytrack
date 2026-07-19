// Exercises the real generated BLS pack, not a fixture.
//
// The pack is a build artifact, so these tests are what catch an ETL change
// that silently drops rows, breaks the FTS index, or loses the distinction
// between "zero" and "not measured".

import 'package:easytrack/data/db/reference_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ReferenceDatabase ref;

  setUpAll(() => ref = ReferenceDatabase.openAt('assets/data/bls.sqlite'));
  tearDownAll(() => ref.dispose());

  List<Map<String, dynamic>> search(String query, {int limit = 10}) {
    return ref.raw
        .select(
          '''
        SELECT f.bls_code, f.name_de, f.kcal, f.protein_g, f.fat_g
        FROM bls_fts JOIN bls_foods f ON f.id = bls_fts.rowid
        WHERE bls_fts MATCH ?
        ORDER BY bm25(bls_fts)
        LIMIT ?''',
          [query, limit],
        )
        .map((r) => {for (final k in r.keys) k: r[k]})
        .toList();
  }

  group('pack integrity', () {
    test('contains the full BLS 4.0 catalogue', () {
      final count =
          ref.raw.select('SELECT COUNT(*) c FROM bls_foods').first['c'] as int;
      expect(count, 7140);
      expect(ref.foodCount, 7140);
    });

    test('declares a schema version this build understands', () {
      expect(
        int.parse(ref.meta['schema_version']!),
        lessThanOrEqualTo(ReferenceDatabase.supportedSchemaVersion),
      );
    });

    test('carries the attribution the licence requires', () {
      // CC BY 4.0 obliges the app to credit the Max Rubner-Institut, so the
      // citation travels inside the pack rather than being hardcoded in the UI
      // where a pack update could leave it stale.
      expect(ref.blsCitation, contains('Max Rubner-Institut'));
      expect(ref.blsCitation, contains('4.0'));
      expect(ref.meta['bls_license'], 'CC BY 4.0');
    });

    test('every food has calories', () {
      final missing =
          ref.raw
                  .select('SELECT COUNT(*) c FROM bls_foods WHERE kcal IS NULL')
                  .first['c']
              as int;
      expect(missing, 0);
    });

    test('every food has a non-empty name and search text', () {
      final bad =
          ref.raw.select('''
            SELECT COUNT(*) c FROM bls_foods
            WHERE name_de IS NULL OR TRIM(name_de) = ''
               OR search_text IS NULL OR TRIM(search_text) = ''
          ''').first['c']
              as int;
      expect(bad, 0);
    });

    test('calories are physically plausible', () {
      // Nothing edible exceeds pure fat at 900 kcal/100 g.
      final impossible =
          ref.raw
                  .select(
                    'SELECT COUNT(*) c FROM bls_foods WHERE kcal < 0 OR kcal > 950',
                  )
                  .first['c']
              as int;
      expect(impossible, 0);
    });
  });

  group('missing values', () {
    test('unmeasured nutrients are NULL, never silently zero', () {
      // docs/bls-format.md: "-" means not determined. If the ETL mapped it to
      // 0 this count would be 0 and unmeasured foods would read as fat-free.
      final nullFat =
          ref.raw
                  .select(
                    'SELECT COUNT(*) c FROM bls_foods WHERE fat_g IS NULL',
                  )
                  .first['c']
              as int;
      expect(nullFat, greaterThan(0));
      expect(nullFat, lessThan(50), reason: 'BLS fat coverage is ~99.6%');
    });

    test('below-detection sentinels became real zeroes', () {
      final zeroAlcohol =
          ref.raw
                  .select(
                    'SELECT COUNT(*) c FROM bls_foods WHERE alcohol_g = 0',
                  )
                  .first['c']
              as int;
      expect(zeroAlcohol, greaterThan(1000));
    });
  });

  group('German search', () {
    test('finds an exact common food', () {
      final results = search('haferflocken OR (hafer AND flocken)');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['name_de'] as String).contains('Hafer')),
        isTrue,
      );
    });

    test('umlaut spellings converge on the same results', () {
      // Both "Käse" and "Kaese" normalize to kaese before reaching FTS.
      final results = search('kaese');
      expect(results, isNotEmpty);
      expect(
        results.every(
          (r) => (r['name_de'] as String).toLowerCase().contains('käse'),
        ),
        isTrue,
        reason: 'every hit should genuinely be a cheese product',
      );
    });

    test('sharp-s spellings are findable', () {
      expect(search('weissbrot'), isNotEmpty);
      expect(search('griess'), isNotEmpty);
    });

    test('compound words are findable by their parts', () {
      // The payoff of the ETL-time morpheme split: "Mehrkornbrötchen" has no
      // token starting with "korn", so prefix matching alone would miss it.
      final korn = search('korn', limit: 30);
      expect(
        korn.any((r) => (r['name_de'] as String).contains('Mehrkorn')),
        isTrue,
      );

      final brot = search('brot', limit: 30);
      expect(
        brot.any((r) => (r['name_de'] as String).contains('Roggen')),
        isTrue,
      );
    });

    test('a plain query returns sensible German staples', () {
      final apfel = search('apfel');
      expect(apfel, isNotEmpty);
      expect(apfel.first['name_de'], contains('Apfel'));
    });

    test('prepared dishes are present, not just raw ingredients', () {
      // BLS groups X and Y are dishes and soups: over a quarter of the data,
      // and what makes logging home-cooked meals practical.
      final dishes =
          ref.raw.select('''
            SELECT COUNT(*) c FROM bls_foods
            WHERE bls_code LIKE 'X%' OR bls_code LIKE 'Y%'
          ''').first['c']
              as int;
      expect(dishes, greaterThan(2000));
    });

    test('food groups are labelled', () {
      final row = ref.raw
          .select(
            "SELECT food_group FROM bls_foods WHERE bls_code LIKE 'B%' LIMIT 1",
          )
          .first;
      expect(row['food_group'], 'Brot');
    });
  });
}
