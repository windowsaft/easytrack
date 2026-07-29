/// Whether a food is measured by mass (grams) or volume (millilitres).
///
/// Drinks are logged and displayed in ml; everything else in g. Nutrients are
/// stored per 100 units regardless, and scaled with the 1 ml ≈ 1 g convention
/// beverages use — accurate enough next to the label rounding real data carries.
enum MeasureUnit {
  grams('g'),
  milliliters('ml');

  const MeasureUnit(this.suffix);

  /// The unit shown after an amount: "g" or "ml".
  final String suffix;

  bool get isLiquid => this == MeasureUnit.milliliters;

  /// Stored form. The suffix doubles as the wire value.
  String get wire => suffix;

  static MeasureUnit fromWire(String? value) =>
      value == 'ml' ? MeasureUnit.milliliters : MeasureUnit.grams;
}

/// Best-effort drink detection, category first (as requested), with a German
/// name-keyword fallback for drinks that sit in a non-beverage category — BLS
/// files juices under "Obst", for instance.
///
/// [category] is a single group/category string (BLS food group, a custom
/// food's group); [categoryTags] is Open Food Facts' `categories_tags` list.
MeasureUnit detectMeasure({
  String? category,
  String? name,
  Iterable<String>? categoryTags,
}) {
  // BLS beverage groups are "Kaffee & Tee" and "Alkoholische Getränke"; the
  // generic "getränk" also catches any custom group the user might type.
  const categoryNeedles = ['getränk', 'kaffee & tee'];
  // Open Food Facts category leaves whose final segment names a drink class.
  // Matched as the LAST hyphen-segment of a tag (after the "en:"/"de:"/"fr:"
  // language prefix), never as a loose substring — so "en:sodas" and
  // "en:fruit-juices" are drinks while "en:watermelons" (…melons), "en:steaks"
  // (…steaks), "en:coffee-beans" (…beans) and "en:tea-bags" (…bags) stay solid.
  // Plural only: the singular forms hide inside solids ("bicarbonates-of-soda",
  // "…-in-juice", "chocolates-with-coffee").
  const beverageLeaves = {
    'beverages',
    'drinks',
    'sodas',
    'juices',
    'nectars',
    'waters',
    'teas',
    'coffees',
    'smoothies',
    'boissons',
  };
  // Substring drink words: these form German compounds ("Apfelsaft",
  // "Zitronenlimonade", "Pfirsicheistee"), so a plain substring match is what
  // catches them. Every word here is safe as a substring — none hides inside a
  // common solid.
  const nameNeedles = [
    'saft',
    'limonade',
    'schorle',
    'smoothie',
    'eistee',
    'energydrink',
    'espresso',
    'cappuccino',
    'prosecco',
    'likör',
    'glühwein',
    'punsch',
  ];
  // Whole-word drink names that DO hide inside common solids as substrings, so
  // they may only match as standalone words: "cola" in Rucola, "spezi" in
  // Spezial, "kola" the Fritz-Kola spelling. A hyphen or space counts as a word
  // boundary, so "Coca-Cola", "Fritz-Kola" and "Paulaner Spezi" all match while
  // "Rucola" and "Spezialbrot" do not. Words still excluded because they are
  // ambiguous even as whole words: "milch"/"wein"/"wasser" (and their compounds
  // Rotwein/Mineralwasser, which no substring or word rule separates cleanly).
  final wordNeedles = RegExp(r'\b(?:cola|kola|spezi)\b');

  bool anyIn(String? haystack, List<String> needles) {
    if (haystack == null) return false;
    final lower = haystack.toLowerCase();
    return needles.any(lower.contains);
  }

  // A tags string signals a drink when any tag's final segment is a beverage
  // leaf. OFF umbrella slugs that lump food AND drink together end in a beverage
  // word too ("en:plant-based-foods-and-beverages", "…-foods-and-drinks"); they
  // carry no measure signal and must be skipped, or every plant food reads as a
  // drink. The tags arrive space-joined from the local pack and one-per-element
  // from the live API, so split each element to handle both.
  bool tagsSignalDrink(String tags) {
    for (final raw in tags.toLowerCase().split(RegExp(r'\s+'))) {
      if (raw.isEmpty) continue;
      final slug = raw.split(':').last; // drop the language prefix
      if (slug.contains('foods-and-beverages') ||
          slug.contains('foods-and-drinks')) {
        continue;
      }
      if (beverageLeaves.contains(slug.split('-').last)) return true;
    }
    return false;
  }

  if (anyIn(category, categoryNeedles)) return MeasureUnit.milliliters;
  if (categoryTags != null && categoryTags.any(tagsSignalDrink)) {
    return MeasureUnit.milliliters;
  }
  if (anyIn(name, nameNeedles)) return MeasureUnit.milliliters;
  if (name != null && wordNeedles.hasMatch(name.toLowerCase())) {
    return MeasureUnit.milliliters;
  }
  return MeasureUnit.grams;
}
