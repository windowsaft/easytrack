import 'package:easytrack/core/nutrition/measure_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectMeasure', () {
    test('BLS beverage groups are millilitres', () {
      expect(
        detectMeasure(category: 'Kaffee & Tee', name: 'Colagetränk'),
        MeasureUnit.milliliters,
      );
      expect(
        detectMeasure(category: 'Alkoholische Getränke', name: 'Pilsner Bier'),
        MeasureUnit.milliliters,
      );
    });

    test('a juice mis-filed under Obst is caught by the name fallback', () {
      expect(
        detectMeasure(category: 'Obst', name: 'Orangensaft'),
        MeasureUnit.milliliters,
      );
    });

    test('Open Food Facts beverage tags are millilitres', () {
      expect(
        detectMeasure(
          name: 'Spezi',
          categoryTags: const ['en:beverages', 'en:sodas'],
        ),
        MeasureUnit.milliliters,
      );
    });

    test('solids stay grams', () {
      expect(
        detectMeasure(category: 'Gemüse', name: 'Rucola roh'),
        MeasureUnit.grams,
      );
      expect(
        detectMeasure(name: 'Haferflocken', categoryTags: const ['en:cereals']),
        MeasureUnit.grams,
      );
    });

    test('cola/spezi drinks are caught by name even without category tags', () {
      // The OFF pack ships no category column, so these reach detectMeasure with
      // a name only — the whole-word fallback has to carry them.
      for (final name in const [
        'Coca-Cola',
        'Cola Zero',
        'Fritz-Kola',
        'Paulaner Spezi',
        'Spezi',
      ]) {
        expect(detectMeasure(name: name), MeasureUnit.milliliters, reason: name);
      }
    });

    test('whole-word drink names do not misfire inside solids', () {
      // "cola" in Rucola, "spezi" in Spezial* must not flip these to millilitres.
      for (final name in const [
        'Rucola roh',
        'Rucolasalat',
        'Spezialbrot',
        'Spezialität des Hauses',
      ]) {
        expect(detectMeasure(name: name), MeasureUnit.grams, reason: name);
      }
    });

    test('ambiguous solids do not misfire on drink substrings', () {
      // "Milch", "Wein", "Wasser" are deliberately not keywords.
      for (final name in const [
        'Milchreis',
        'Weintrauben',
        'Wassermelone',
        'Buttermilch-Brötchen',
      ]) {
        expect(detectMeasure(name: name), MeasureUnit.grams, reason: name);
      }
    });

    test('round-trips through the wire form', () {
      expect(MeasureUnit.fromWire('ml'), MeasureUnit.milliliters);
      expect(MeasureUnit.fromWire('g'), MeasureUnit.grams);
      expect(MeasureUnit.fromWire(null), MeasureUnit.grams);
      expect(MeasureUnit.milliliters.wire, 'ml');
    });
  });
}
