import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/data/db/reference_database.dart';
import 'package:easytrack/data/food/bls_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ReferenceDatabase ref;
  late BlsProvider provider;

  setUpAll(() {
    ref = ReferenceDatabase.openAt('assets/data/bls.sqlite');
    provider = BlsProvider(ref);
  });
  tearDownAll(() => ref.dispose());

  group('buildMatchExpression', () {
    test('quotes tokens and prefixes only the last', () {
      expect(BlsProvider.buildMatchExpression('hafer'), '"hafer"*');
      expect(
        BlsProvider.buildMatchExpression('hafer flocken'),
        '"hafer" AND "flocken"*',
      );
    });

    test('returns null for empty input', () {
      expect(BlsProvider.buildMatchExpression(''), isNull);
      expect(BlsProvider.buildMatchExpression('   '), isNull);
    });
  });

  group('query robustness', () {
    // FTS5 treats bare AND/OR/NOT/*/" as syntax. Unquoted, a user typing any of
    // them mid-word throws SqliteException and the search screen breaks rather
    // than simply finding nothing.
    test('FTS operators in user input do not throw', () async {
      for (final query in [
        'AND',
        'OR',
        'NOT',
        'NEAR',
        '*',
        '"',
        'brot AND',
        'brot OR NOT',
        'brot"',
        'brot*',
        '(brot)',
        '^brot',
        'brot -- kommentar',
        "brot'; DROP TABLE bls_foods; --",
      ]) {
        await expectLater(
          provider.search(query),
          completes,
          reason: 'query: $query',
        );
      }
    });

    test('a destructive-looking query leaves the pack intact', () async {
      await provider.search("brot'; DROP TABLE bls_foods; --");
      final count =
          ref.raw.select('SELECT COUNT(*) c FROM bls_foods').first['c'] as int;
      expect(count, 7140);
    });

    test('empty and whitespace queries return nothing', () async {
      expect(await provider.search(''), isEmpty);
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('!!!'), isEmpty);
    });
  });

  group('search results', () {
    test('finds German staples', () async {
      final results = await provider.search('apfel');
      expect(results, isNotEmpty);
      expect(results.first.item.name, contains('Apfel'));
      expect(results.first.item.ref.source, FoodSourceType.bls);
    });

    test('umlaut and ae spellings return the same food', () async {
      final withUmlaut = await provider.search('käse');
      final withoutUmlaut = await provider.search('kaese');

      expect(withUmlaut, isNotEmpty);
      expect(
        withUmlaut.map((r) => r.item.ref.id).toList(),
        withoutUmlaut.map((r) => r.item.ref.id).toList(),
      );
    });

    test('finds compounds by an interior part', () async {
      final results = await provider.search('korn', limit: 30);
      expect(
        results.any((r) => r.item.name.contains('Mehrkorn')),
        isTrue,
        reason: 'compound splitting should surface Mehrkorn* for "korn"',
      );
    });

    test('supports incremental typing', () async {
      // Each keystroke must keep returning results, not just the finished word.
      for (final partial in ['h', 'ha', 'haf', 'hafe', 'hafer']) {
        expect(
          await provider.search(partial),
          isNotEmpty,
          reason: 'partial query: $partial',
        );
      }
    });

    test('multi-word queries require every word', () async {
      final results = await provider.search('hafer flocken');
      expect(results, isNotEmpty);
      expect(results.first.item.name, contains('Hafer'));
    });

    test('nonsense returns nothing rather than noise', () async {
      expect(await provider.search('xyzzyqwertz'), isEmpty);
    });

    test('scores are higher-is-better', () async {
      final results = await provider.search('brot', limit: 10);
      expect(results.length, greaterThan(1));
      for (final result in results) {
        expect(result.rawScore, greaterThan(0));
      }
    });

    test('respects the limit', () async {
      expect((await provider.search('brot', limit: 3)), hasLength(3));
    });
  });

  group('lookup by id', () {
    test('resolves a known BLS code with usable nutrients', () async {
      final oats = await provider.byId('C133000'); // Hafer Flocken
      expect(oats, isNotNull);
      expect(oats!.name, contains('Hafer'));
      expect(oats.nutrients.kcal, greaterThan(300));
      expect(oats.nutrients.proteinG, greaterThan(0));
      expect(oats.ref, const FoodRef(FoodSourceType.bls, 'C133000'));
    });

    test('nutrients scale correctly to a portion', () async {
      final oats = (await provider.byId('C133000'))!;
      final portion = oats.nutrients.forGrams(50);
      expect(portion.kcal, closeTo(oats.nutrients.kcal / 2, 0.001));
    });

    test('unknown codes return null', () async {
      expect(await provider.byId('ZZZ9999'), isNull);
    });

    test('BLS has no barcodes', () async {
      expect(await provider.byBarcode('4000521006402'), isNull);
    });
  });
}
