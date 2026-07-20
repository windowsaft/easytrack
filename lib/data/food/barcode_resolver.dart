import '../repositories/off_cache_repository.dart';
import 'custom_food_provider.dart';
import 'food_item.dart';
import 'off_api_client.dart';
import 'off_local_provider.dart';

/// The result of resolving a scanned barcode.
sealed class BarcodeOutcome {
  const BarcodeOutcome();
}

/// A product was found in one of the sources.
class BarcodeFound extends BarcodeOutcome {
  const BarcodeFound(this.item);
  final FoodItem item;
}

/// No source knows this barcode; the caller offers a manual entry prefilled
/// with it.
class BarcodeUnknown extends BarcodeOutcome {
  const BarcodeUnknown(this.barcode);
  final String barcode;
}

/// Resolves a barcode through the source chain, fastest-and-freshest first.
///
/// Order — custom foods → online cache → local pack → online API — is
/// deliberate:
///
/// - The user's own foods win: a scanned barcode they saved is exactly what they
///   meant.
/// - The cache comes before the shipped pack because it holds newer data by
///   construction (it was fetched live, after the pack was built) and it lives
///   in the user database, so it survives a pack replacement.
/// - The network is last, and every hit is written back to the cache so the next
///   scan of the same product works offline.
class BarcodeResolver {
  const BarcodeResolver({
    required this.custom,
    required this.cache,
    required this.offApi,
    this.pack,
  });

  final CustomFoodProvider custom;
  final OffCacheRepository cache;
  final OffApiClient offApi;

  /// The installed OFF pack, or null when none is installed.
  final OffLocalProvider? pack;

  Future<BarcodeOutcome> resolve(String barcode) async {
    final fromCustom = await custom.byBarcode(barcode);
    if (fromCustom != null) return BarcodeFound(fromCustom);

    final fromCache = await cache.byBarcode(barcode);
    if (fromCache != null) return BarcodeFound(fromCache);

    final localPack = pack;
    if (localPack != null) {
      final fromPack = await localPack.byBarcode(barcode);
      if (fromPack != null) return BarcodeFound(fromPack);
    }

    final fromApi = await offApi.fetchByBarcode(barcode);
    if (fromApi != null) {
      await cache.cache(fromApi);
      return BarcodeFound(fromApi);
    }

    return BarcodeUnknown(barcode);
  }
}
