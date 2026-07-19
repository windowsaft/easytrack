// Dart half of the normalizer parity check.
//
// The Node half lives in tools/etl/normalize.test.mjs and reads the same
// fixture file. Both must pass: this side builds the search query, that side
// builds the search index, and if they disagree every query silently returns
// nothing.

import 'dart:convert';
import 'dart:io';

import 'package:easytrack/core/text/german_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixtures =
      jsonDecode(
            File('tools/etl/fixtures/normalizer_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  final morphemes = File('tools/etl/de_food_morphemes.txt')
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();

  group('normalizeGerman', () {
    test('matches the shared fixtures', () {
      for (final entry in fixtures['normalize'] as List<dynamic>) {
        final pair = (entry as List<dynamic>).cast<String>();
        expect(
          normalizeGerman(pair[0]),
          pair[1],
          reason: 'normalizeGerman("${pair[0]}")',
        );
      }
    });

    test('emits only a-z, 0-9 and single spaces', () {
      final shape = RegExp(r'^$|^[a-z0-9]+( [a-z0-9]+)*$');
      for (final entry in fixtures['normalize'] as List<dynamic>) {
        final input = (entry as List<dynamic>)[0] as String;
        expect(normalizeGerman(input), matches(shape), reason: 'input: $input');
      }
    });

    test('is idempotent', () {
      for (final entry in fixtures['normalize'] as List<dynamic>) {
        final input = (entry as List<dynamic>)[0] as String;
        final once = normalizeGerman(input);
        expect(normalizeGerman(once), once, reason: 'input: $input');
      }
    });

    test('umlauts expand rather than losing their vowel', () {
      // The failure mode this guards: SQLite's remove_diacritics would fold
      // "Käse" to "kase", which is neither what a user types with an umlaut
      // keyboard nor what they type without one.
      expect(normalizeGerman('Käse'), 'kaese');
      expect(normalizeGerman('Kaese'), normalizeGerman('Käse'));
      expect(normalizeGerman('Käse'), isNot('kase'));
    });

    test('sharp s folds to ss, which remove_diacritics does not do', () {
      expect(normalizeGerman('Weißbrot'), 'weissbrot');
      expect(normalizeGerman('Weissbrot'), normalizeGerman('Weißbrot'));
    });
  });

  group('extractCompoundParts', () {
    test('matches the shared fixtures', () {
      for (final entry in fixtures['compounds'] as List<dynamic>) {
        final row = entry as List<dynamic>;
        final token = row[0] as String;
        final expected = (row[1] as List<dynamic>).cast<String>();
        expect(
          extractCompoundParts(token, morphemes),
          expected,
          reason: 'extractCompoundParts("$token")',
        );
      }
    });

    test('keeps nested stems so a compound is findable by any part', () {
      final parts = extractCompoundParts('vollkornbrot', morphemes);
      expect(parts, contains('korn'));
      expect(parts, contains('brot'));
      expect(parts, contains('vollkorn'));
    });

    test('never emits the whole token as its own part', () {
      for (final token in ['haferflocken', 'kartoffelsalat', 'apfelschorle']) {
        expect(extractCompoundParts(token, morphemes), isNot(contains(token)));
      }
    });

    test('short tokens are left alone', () {
      expect(extractCompoundParts('brot', morphemes), isEmpty);
      expect(extractCompoundParts('apfel', morphemes), isEmpty);
    });
  });

  group('buildSearchText', () {
    test('matches the shared fixtures', () {
      for (final entry in fixtures['searchText'] as List<dynamic>) {
        final row = entry as Map<String, dynamic>;
        expect(
          buildSearchText(
            row['name'] as String,
            brand: row['brand'] as String?,
            morphemes: morphemes,
          ),
          row['expected'] as String,
          reason: 'buildSearchText("${row['name']}")',
        );
      }
    });

    test('the original name leads, so exact matches still rank first', () {
      final text = buildSearchText('Vollkornbrot', morphemes: morphemes);
      expect(text.startsWith('vollkornbrot'), isTrue);
    });

    test('a part already present as its own word is not repeated', () {
      final tokens = buildSearchText(
        'Brot Vollkornbrot',
        morphemes: morphemes,
      ).split(' ');

      // "brot" stands alone in the name, so the compound must not add it again.
      // Counted as whole tokens: "vollkornbrot" ends in "brot" and would fool a
      // substring check.
      expect(tokens.where((t) => t == 'brot').length, 1);
      expect(tokens, containsAll(['brot', 'vollkornbrot', 'vollkorn', 'korn']));
    });

    test('without morphemes it degrades to plain normalization', () {
      expect(buildSearchText('Vollkornbrot'), 'vollkornbrot');
    });
  });

  group('morpheme list', () {
    test('is in normalized form and meets the length floor', () {
      for (final morpheme in morphemes) {
        expect(
          normalizeGerman(morpheme),
          morpheme,
          reason: '"$morpheme" is not normalized',
        );
        expect(
          morpheme.length,
          greaterThanOrEqualTo(4),
          reason: '"$morpheme" is too short',
        );
      }
    });

    test('is large enough to be worth the lookup', () {
      expect(morphemes.length, greaterThan(200));
    });
  });
}
