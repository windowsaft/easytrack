import 'dart:io';

import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/data/food/off_local_provider.dart';
import 'package:easytrack/data/pack/off_pack_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/off_pack_fixture.dart';

void main() {
  late Directory dir;
  late OffPackDatabase pack;
  late OffLocalProvider provider;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('off-prov-');
    final path = '${dir.path}/off.sqlite';
    writeOffPack(path);
    pack = OffPackDatabase.openAt(path);
    provider = OffLocalProvider(pack);
  });

  tearDown(() {
    pack.dispose();
    dir.deleteSync(recursive: true);
  });

  test('reports its source, weight and offline availability', () async {
    expect(provider.source, FoodSourceType.offLocal);
    expect(provider.sourceWeight, 0.85);
    expect(provider.requiresNetwork, isFalse);
    expect(await provider.isAvailable(), isTrue);
  });

  test('finds a product by name', () async {
    final hits = await provider.search('cola');
    expect(hits, isNotEmpty);
    expect(hits.first.item.name, 'Coca-Cola');
    expect(hits.first.item.ref.source, FoodSourceType.offLocal);
  });

  test('finds a product by its brand', () async {
    // "Nutella" is a brand, not in the product name — it reaches the row via
    // the brand folded into search_text.
    final hits = await provider.search('nutella');
    expect(hits.any((r) => r.item.name == 'Nuss-Nougat-Creme'), isTrue);
  });

  test('resolves a barcode to a product with its serving', () async {
    final item = await provider.byBarcode('5449000000996');
    expect(item, isNotNull);
    expect(item!.name, 'Coca-Cola');
    expect(item.barcode, '5449000000996');
    // The declared serving is offered alongside the 100 g fallback.
    expect(item.servings.single.grams, 250);
    expect(item.nutrients.kcal, 42);
  });

  test('byId is barcode resolution', () async {
    final item = await provider.byId('3017620422003');
    expect(item?.name, 'Nuss-Nougat-Creme');
    expect(item?.brand, contains('Ferrero'));
  });

  test('an unknown barcode resolves to null', () async {
    expect(await provider.byBarcode('0000000000000'), isNull);
  });
}
