import 'dart:convert';
import 'dart:io';

import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/barcode_resolver.dart';
import 'package:easytrack/data/food/custom_food_provider.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/food/off_api_client.dart';
import 'package:easytrack/data/food/off_local_provider.dart';
import 'package:easytrack/data/pack/off_pack_database.dart';
import 'package:easytrack/data/repositories/custom_food_repository.dart';
import 'package:easytrack/data/repositories/off_cache_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/off_pack_fixture.dart';

void main() {
  late UserDatabase db;
  late CustomFoodRepository customRepo;
  late OffCacheRepository cache;

  setUp(() {
    db = UserDatabase.forTesting();
    customRepo = CustomFoodRepository(db);
    cache = OffCacheRepository(db);
  });
  tearDown(() => db.close());

  Map<String, dynamic> product(String name) => {
    'product_name': name,
    'brands': 'Marke',
    'nutriments': {'energy-kcal_100g': 100, 'carbohydrates_100g': 20},
  };

  /// A client that knows [known] barcodes, records whether it was hit, and
  /// answers "unknown" (status 0) otherwise.
  OffApiClient apiWith(Map<String, String> known, {void Function()? onCall}) =>
      OffApiClient(
        client: MockClient((request) async {
          onCall?.call();
          final code = request.url.pathSegments.last.replaceAll('.json', '');
          final name = known[code];
          if (name == null) {
            return http.Response(jsonEncode({'status': 0}), 200);
          }
          return http.Response(
            jsonEncode({'status': 1, 'product': product(name)}),
            200,
          );
        }),
      );

  BarcodeResolver resolver({
    required OffApiClient offApi,
    OffLocalProvider? pack,
  }) => BarcodeResolver(
    custom: CustomFoodProvider(db),
    cache: cache,
    offApi: offApi,
    pack: pack,
  );

  test('the user\'s own food wins over everything', () async {
    await customRepo.create(
      name: 'Mein Riegel',
      nutrients: const Nutrients(kcal: 400, proteinG: 20, carbsG: 40, fatG: 15),
      barcode: '1111',
    );
    var apiHit = false;
    final outcome = await resolver(
      offApi: apiWith(const {
        '1111': 'Sollte nicht gewinnen',
      }, onCall: () => apiHit = true),
    ).resolve('1111');

    expect(outcome, isA<BarcodeFound>());
    final item = (outcome as BarcodeFound).item;
    expect(item.name, 'Mein Riegel');
    expect(item.ref.source, FoodSourceType.custom);
    expect(apiHit, isFalse, reason: 'a local hit must not touch the network');
  });

  test('the cache is consulted before the network', () async {
    await cache.cache(
      FoodItem(
        ref: const FoodRef(FoodSourceType.offOnline, '2222'),
        name: 'Gecacht',
        barcode: '2222',
        nutrients: const Nutrients(kcal: 50, proteinG: 1, carbsG: 5, fatG: 1),
      ),
    );
    var apiHit = false;
    final outcome = await resolver(
      offApi: apiWith(const {'2222': 'Frisch'}, onCall: () => apiHit = true),
    ).resolve('2222');

    expect((outcome as BarcodeFound).item.name, 'Gecacht');
    expect(apiHit, isFalse);
  });

  test('a pack hit short-circuits the network', () async {
    final dir = Directory.systemTemp.createTempSync('br-pack-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/off.sqlite';
    writeOffPack(path);
    final pack = OffPackDatabase.openAt(path);
    addTearDown(pack.dispose);

    var apiHit = false;
    final outcome = await resolver(
      offApi: apiWith(const {}, onCall: () => apiHit = true),
      pack: OffLocalProvider(pack),
    ).resolve('5449000000996');

    expect((outcome as BarcodeFound).item.name, 'Coca-Cola');
    expect((outcome).item.ref.source, FoodSourceType.offLocal);
    expect(apiHit, isFalse);
  });

  test('an online hit is returned and written to the cache', () async {
    expect(await cache.byBarcode('3333'), isNull);

    final outcome = await resolver(
      offApi: apiWith(const {'3333': 'Online-Produkt'}),
    ).resolve('3333');

    expect((outcome as BarcodeFound).item.name, 'Online-Produkt');
    // Cached, so the next scan is offline.
    expect((await cache.byBarcode('3333'))!.name, 'Online-Produkt');
  });

  test('a barcode no source knows resolves to unknown', () async {
    final outcome = await resolver(offApi: apiWith(const {})).resolve('9999');
    expect(outcome, isA<BarcodeUnknown>());
    expect((outcome as BarcodeUnknown).barcode, '9999');
  });
}
