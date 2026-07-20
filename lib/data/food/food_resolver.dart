import '../../core/nutrition/food_ref.dart';
import '../repositories/off_cache_repository.dart';
import 'food_item.dart';
import 'food_provider.dart';

/// Turns a bare [FoodRef] back into a full [FoodItem].
///
/// Needed wherever the app holds a reference without the nutrients — a pinned
/// favourite, a re-log candidate. Dispatches by source to the provider that owns
/// it; the online cache covers `offOnline`, which is not a search provider but
/// still holds every product ever scanned.
///
/// Returns null when the source is currently unavailable — a pinned OFF product
/// while its pack is uninstalled, say — so the caller can show the name alone
/// rather than a wrong number.
class FoodResolver {
  const FoodResolver({required this.providers, required this.cache});

  final List<FoodProvider> providers;
  final OffCacheRepository cache;

  Future<FoodItem?> resolve(FoodRef ref) async {
    for (final provider in providers) {
      if (provider.source == ref.source) {
        return provider.byId(ref.id);
      }
    }
    if (ref.source == FoodSourceType.offOnline) {
      return cache.byBarcode(ref.id);
    }
    return null;
  }
}
