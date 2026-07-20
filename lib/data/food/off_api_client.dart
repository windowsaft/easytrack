import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import 'food_item.dart';

/// Looks up a barcode against the live Open Food Facts API.
///
/// The last link in the barcode chain, tried only when the product is in none
/// of the offline sources. Deliberately forgiving: a timeout, a network error,
/// a not-found or an unparseable body all resolve to null — "not found online" —
/// so the caller can fall through to offering a manual entry rather than showing
/// an error for what is a routine miss.
class OffApiClient {
  OffApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 3),
    this.baseUrl = 'https://world.openfoodfacts.org',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final String baseUrl;

  /// Open Food Facts asks every client to identify itself; an anonymous or
  /// browser-like agent risks being rate-limited or blocked.
  static const _userAgent =
      'EasyTrack/1.0 (personal offline calorie tracker; Flutter)';

  /// Only the fields the app uses, to keep the response small.
  static const _fields = 'product_name,brands,serving_quantity,nutriments';

  Future<FoodItem?> fetchByBarcode(String barcode) async {
    final uri = Uri.parse(
      '$baseUrl/api/v2/product/$barcode.json?fields=$_fields',
    );
    try {
      final response = await _client
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(timeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // status 1 = found, 0 = unknown barcode.
      if (json['status'] != 1) return null;
      final product = json['product'];
      if (product is! Map<String, dynamic>) return null;

      return parseProduct(barcode, product);
    } catch (_) {
      // Timeout, socket error, bad JSON — all "not found online".
      return null;
    }
  }

  /// Builds a [FoodItem] from an OFF `product` object. Public so the parsing is
  /// unit-testable against a canned response without a live request.
  ///
  /// Returns null when the product has no usable energy value — a food we cannot
  /// state the calories of is not worth logging, and would only mislead.
  static FoodItem? parseProduct(String barcode, Map<String, dynamic> product) {
    final nutriments = product['nutriments'];
    if (nutriments is! Map<String, dynamic>) return null;

    double? per100(String key) {
      final value = nutriments['${key}_100g'];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.replaceAll(',', '.'));
      return null;
    }

    final kcal = per100('energy-kcal');
    if (kcal == null) return null;

    final name = (product['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final brands = (product['brands'] as String?)?.trim();

    final serving = _grams(product['serving_quantity']);

    return FoodItem(
      ref: FoodRef(FoodSourceType.offOnline, barcode),
      name: name,
      brand: brands != null && brands.isNotEmpty ? brands : null,
      barcode: barcode,
      nutrients: Nutrients(
        kcal: kcal,
        proteinG: per100('proteins') ?? 0,
        carbsG: per100('carbohydrates') ?? 0,
        fatG: per100('fat') ?? 0,
        sugarG: per100('sugars'),
        fiberG: per100('fiber'),
        satFatG: per100('saturated-fat'),
        saltG: per100('salt'),
      ),
      servings: [
        if (serving != null && serving > 0)
          ServingOption(
            label: '1 Portion (${_trim(serving)} g)',
            grams: serving,
          ),
      ],
    );
  }

  static double? _grams(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
    return null;
  }

  static String _trim(double g) =>
      g == g.roundToDouble() ? g.round().toString() : g.toStringAsFixed(1);

  void close() => _client.close();
}
