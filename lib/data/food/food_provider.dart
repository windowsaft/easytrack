import '../../core/nutrition/food_ref.dart';
import 'food_item.dart';

/// A searchable source of foods.
///
/// Implemented by the bundled BLS pack, the user's own foods and recipes, the
/// downloaded Open Food Facts pack, the Open Food Facts API and — later — USDA.
/// Adding a source means writing one of these and registering it with the
/// orchestrator; nothing else in the app changes, because diary entries
/// reference `(sourceType, sourceId)` and carry their own nutrient snapshot.
abstract class FoodProvider {
  FoodSourceType get source;

  /// Weight applied to this provider's normalized scores when results merge.
  ///
  /// The user's own foods outrank everything because they typed them. BLS
  /// outranks Open Food Facts because its entries are lab-grade generics that
  /// match how people log home-cooked food, whereas branded products are better
  /// reached by barcode than by typing.
  double get sourceWeight;

  bool get requiresNetwork;

  /// Cheap check — pack installed, network reachable. Must never throw.
  Future<bool> isAvailable();

  Future<List<FoodSearchResult>> search(String query, {int limit = 30});

  /// Resolves a barcode, or null if this source does not know it.
  Future<FoodItem?> byBarcode(String barcode);

  /// Resolves a source-specific id: BLS code, barcode, or UUID.
  Future<FoodItem?> byId(String id);
}
