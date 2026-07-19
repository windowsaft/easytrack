/// Normalizes German food names for search.
///
/// This logic is mirrored in `tools/etl/normalize.mjs`, which builds the search
/// index. If the two ever disagree the index says `kaese` while the query says
/// `käse`, and search silently returns nothing — so both sides are checked
/// against the shared fixtures in `tools/etl/fixtures/normalizer_cases.json`.
///
/// Umlauts are expanded (ä->ae) rather than stripped (ä->a). SQLite's
/// `remove_diacritics` would produce `kase`, which nobody types; German
/// keyboards without umlauts produce `kaese`. `ß` is not a diacritic at all and
/// `remove_diacritics` leaves it alone, so it is handled here too. The FTS
/// tokenizer therefore runs with `remove_diacritics 0` — all folding happens
/// in this function, on both sides.
library;

/// Expanded before accent folding, so `ä` becomes `ae` and not `a`.
const _germanExpansions = <String, String>{
  'ä': 'ae',
  'ö': 'oe',
  'ü': 'ue',
  'ß': 'ss',
};

/// Accents that carry no meaning in German food names.
///
/// Dart has no Unicode normalization in its core library, so this is an
/// explicit map rather than an NFD decomposition. The set is limited to what
/// actually appears in German, French and Scandinavian food names.
const _accentFolding = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ý': 'y',
  'æ': 'ae',
  'œ': 'oe',
};

/// Folds a string to its searchable form.
///
/// Lowercases, expands umlauts and `ß`, folds remaining accents, reduces
/// everything that is not a letter or digit to a space, and collapses runs of
/// whitespace. The result contains only `a-z`, `0-9` and single spaces.
String normalizeGerman(String input) {
  if (input.isEmpty) return '';

  final lower = input.toLowerCase();
  final buffer = StringBuffer();

  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);

    final expanded = _germanExpansions[ch];
    if (expanded != null) {
      buffer.write(expanded);
      continue;
    }

    final folded = _accentFolding[ch];
    if (folded != null) {
      buffer.write(folded);
      continue;
    }

    // Keep ASCII letters and digits; everything else becomes a separator so
    // that "Vollkorn-Brot", "Vollkorn/Brot" and "Vollkorn, Brot" all agree.
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isLetter = rune >= 0x61 && rune <= 0x7A;
    buffer.write(isDigit || isLetter ? ch : ' ');
  }

  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Minimum length of a morpheme to be considered a real word part.
///
/// Below four characters the matches are mostly noise — "ei" would fire inside
/// "Eiweiss", "Eintopf" and "Feige" alike.
const _minMorphemeLength = 4;

/// Length above which a token is treated as a possible compound.
const _minCompoundLength = 9;

/// Finds the food morphemes hidden inside German compound words.
///
/// "Vollkornbrot" is one token, so a search for "brot" cannot match it: FTS5
/// prefix queries only match from the start. Rather than pay for a trigram
/// index — 4-6x larger and destructive to relevance ranking — the parts are
/// found once at index time and appended to the indexed text.
///
/// Takes the longest match at each start position, then advances by one
/// character rather than skipping past the match. Segmenting the word instead
/// would consume "vollkorn" as one piece and never emit "korn", so
/// "Vollkornbrot" would not be findable by "korn" — which is the entire point.
///
/// Returns only the extra tokens; the caller keeps the original word too.
List<String> extractCompoundParts(String token, Set<String> morphemes) {
  if (token.length < _minCompoundLength) return const [];

  final parts = <String>[];
  final seen = <String>{};

  for (var start = 0; start + _minMorphemeLength <= token.length; start++) {
    for (var end = token.length; end >= start + _minMorphemeLength; end--) {
      final candidate = token.substring(start, end);
      if (!morphemes.contains(candidate)) continue;
      if (candidate.length != token.length && seen.add(candidate)) {
        parts.add(candidate);
      }
      break; // longest match at this position wins
    }
  }

  return parts;
}

/// Builds the text stored in the search index for a food name.
///
/// The original normalized name comes first so that exact and prefix matches
/// still score highest, with any compound parts appended.
String buildSearchText(
  String name, {
  String? brand,
  Set<String> morphemes = const {},
}) {
  final normalized = normalizeGerman(
    brand == null || brand.isEmpty ? name : '$name $brand',
  );
  if (normalized.isEmpty || morphemes.isEmpty) return normalized;

  final extra = <String>{};
  for (final token in normalized.split(' ')) {
    extra.addAll(extractCompoundParts(token, morphemes));
  }
  // Do not repeat a part that already stands alone in the name.
  extra.removeAll(normalized.split(' '));

  return extra.isEmpty ? normalized : '$normalized ${extra.join(' ')}';
}
