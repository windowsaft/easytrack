/// Where a food came from.
///
/// Persisted by name (see [FoodSourceType.wireName]) rather than by index, so
/// adding a source later cannot renumber existing rows.
enum FoodSourceType {
  /// A food the user created by hand.
  custom('custom'),

  /// Bundeslebensmittelschlüssel 4.0 — bundled German reference data.
  bls('bls'),

  /// Open Food Facts, from the downloaded offline product pack.
  offLocal('off_local'),

  /// Open Food Facts, fetched live from the API.
  offOnline('off_online'),

  /// USDA FoodData Central. Not implemented yet.
  usda('usda'),

  /// A user-defined recipe logged as a single item.
  recipe('recipe');

  const FoodSourceType(this.wireName);

  final String wireName;

  static FoodSourceType fromWire(String value) => values.firstWhere(
    (e) => e.wireName == value,
    orElse: () => throw ArgumentError('unknown food source: $value'),
  );

  /// Label shown on the source chip in search results and food details.
  String get displayLabel => switch (this) {
    FoodSourceType.custom => 'Eigenes Lebensmittel',
    FoodSourceType.bls => 'BLS 4.0',
    FoodSourceType.offLocal || FoodSourceType.offOnline => 'Open Food Facts',
    FoodSourceType.usda => 'USDA',
    FoodSourceType.recipe => 'Rezept',
  };

  bool get isUserOwned =>
      this == FoodSourceType.custom || this == FoodSourceType.recipe;
}

/// A stable pointer to a food in any source.
///
/// Diary entries and recipe ingredients store this pair rather than a foreign
/// key, because the target may live in the replaceable reference database, in
/// the user database, or only on a remote server.
class FoodRef {
  const FoodRef(this.source, this.id);

  final FoodSourceType source;

  /// BLS code, barcode, custom-food UUID or recipe UUID depending on [source].
  final String id;

  @override
  bool operator ==(Object other) =>
      other is FoodRef && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => '${source.wireName}:$id';
}

/// The four meals a day is divided into.
enum MealType {
  breakfast('breakfast', 'Frühstück'),
  lunch('lunch', 'Mittagessen'),
  dinner('dinner', 'Abendessen'),
  snacks('snacks', 'Snacks');

  const MealType(this.wireName, this.displayLabel);

  final String wireName;
  final String displayLabel;

  static MealType fromWire(String value) => values.firstWhere(
    (e) => e.wireName == value,
    orElse: () => throw ArgumentError('unknown meal: $value'),
  );
}
