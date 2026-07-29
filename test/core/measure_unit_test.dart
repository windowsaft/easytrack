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

    test('the OFF food+drink umbrella tag does not flip solids to millilitres', () {
      // OFF tags almost every plant food with "en:plant-based-foods-and-beverages",
      // whose slug ends in "beverages" — it must not be read as a drink. Both the
      // local pack (one space-joined string) and the live API (one tag per element)
      // shapes have to stay grams.
      expect(
        detectMeasure(
          name: 'Kaiserbrötchen',
          categoryTags: const [
            'en:plant-based-foods-and-beverages en:cereals-and-potatoes '
                'en:breads en:white-breads en:bread-rolls',
          ],
        ),
        MeasureUnit.grams,
      );
      expect(
        detectMeasure(
          name: 'Kaiserbrötchen',
          categoryTags: const ['en:plant-based-foods-and-beverages', 'en:breads'],
        ),
        MeasureUnit.grams,
      );
    });

    test('reported OFF products stay grams', () {
      // The real tag strings that used to misfire on the "beverages" substring.
      const cases = {
        'Belegkirschen':
            'en:plant-based-foods-and-beverages en:plant-based-foods '
                'en:snacks en:sweet-snacks en:confectioneries en:candied-fruits',
        'Baguetterie':
            'en:plant-based-foods-and-beverages en:plant-based-foods '
                'en:cereals-and-potatoes en:breads en:baguettes',
      };
      cases.forEach((name, tags) {
        expect(
          detectMeasure(name: name, categoryTags: [tags]),
          MeasureUnit.grams,
          reason: name,
        );
      });
    });

    test('drink words hidden mid-tag do not flip solids to millilitres', () {
      // The substring bug: "tea" inside "en:steaks"/"en:gateaux" and "water"
      // inside "en:watermelons". None of these carry a real beverage ancestor, so
      // last-segment matching keeps them grams. (Real tag strings from the pack.)
      const solids = {
        'Rindersteak':
            'en:meats en:beef en:steaks en:beef-steaks en:ground-steaks',
        'Wassermelone':
            'en:plant-based-foods-and-beverages en:plant-based-foods '
                'en:fruit-based-foods-and-beverages en:fruits en:melons '
                'en:watermelons',
        'Gâteau':
            'en:snacks en:sweet-snacks en:biscuits-and-cakes en:cakes '
                'en:biscuits-et-gateaux en:gateaux',
      };
      solids.forEach((name, tags) {
        expect(
          detectMeasure(name: name, categoryTags: [tags]),
          MeasureUnit.grams,
          reason: name,
        );
      });
    });

    test('real OFF beverage leaves are millilitres', () {
      const drinks = {
        'Traubensaft':
            'en:plant-based-foods-and-beverages en:beverages en:fruit-juices',
        'Cola': 'en:sodas',
        'Energydrink': 'en:carbonated-drinks',
        'Mineralwasser': 'en:waters en:mineral-waters',
        'Schwarztee': 'en:teas',
        'Filterkaffee': 'en:coffees',
      };
      drinks.forEach((name, tags) {
        expect(
          detectMeasure(name: name, categoryTags: [tags]),
          MeasureUnit.milliliters,
          reason: name,
        );
      });
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
