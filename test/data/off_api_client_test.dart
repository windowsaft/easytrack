import 'dart:convert';

import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/data/food/off_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> cola() => {
  'product_name': 'Coca-Cola',
  'brands': 'Coca-Cola',
  'serving_quantity': 250,
  'nutriments': {
    'energy-kcal_100g': 42,
    'proteins_100g': 0,
    'carbohydrates_100g': 10.6,
    'fat_100g': 0,
    'sugars_100g': 10.6,
    'salt_100g': 0,
  },
};

void main() {
  group('parseProduct', () {
    test('maps a product to a per-100 g food with its serving', () {
      final item = OffApiClient.parseProduct('5449000000996', cola())!;
      expect(item.ref.source, FoodSourceType.offOnline);
      expect(item.name, 'Coca-Cola');
      expect(item.brand, 'Coca-Cola');
      expect(item.barcode, '5449000000996');
      expect(item.nutrients.kcal, 42);
      expect(item.nutrients.carbsG, 10.6);
      expect(item.servings.single.grams, 250);
    });

    test('rejects a product with no energy value', () {
      final noEnergy = cola()..['nutriments'] = {'proteins_100g': 1};
      expect(OffApiClient.parseProduct('x', noEnergy), isNull);
    });

    test('rejects a product with no name', () {
      final noName = cola()..['product_name'] = '';
      expect(OffApiClient.parseProduct('x', noName), isNull);
    });

    test('parses string-encoded numbers with a decimal comma', () {
      final stringy = cola()
        ..['serving_quantity'] = '30'
        ..['nutriments'] = {'energy-kcal_100g': '42,5'};
      final item = OffApiClient.parseProduct('x', stringy)!;
      expect(item.nutrients.kcal, 42.5);
      expect(item.servings.single.grams, 30);
    });
  });

  group('fetchByBarcode', () {
    test('returns the product on a found response', () async {
      final client = OffApiClient(
        client: MockClient((request) async {
          expect(request.headers['User-Agent'], contains('EasyTrack'));
          return http.Response(
            jsonEncode({'status': 1, 'product': cola()}),
            200,
          );
        }),
      );
      final item = await client.fetchByBarcode('5449000000996');
      expect(item?.name, 'Coca-Cola');
    });

    test('returns null for an unknown barcode (status 0)', () async {
      final client = OffApiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': 0}), 200),
        ),
      );
      expect(await client.fetchByBarcode('0000'), isNull);
    });

    test('returns null on a non-200 response', () async {
      final client = OffApiClient(
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      expect(await client.fetchByBarcode('0000'), isNull);
    });

    test('returns null when the request throws', () async {
      final client = OffApiClient(
        client: MockClient((_) async => throw const _Boom()),
      );
      expect(await client.fetchByBarcode('0000'), isNull);
    });
  });
}

class _Boom implements Exception {
  const _Boom();
}
