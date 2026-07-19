// German search normalizer — the ETL half.
//
// MIRRORS lib/core/text/german_normalizer.dart. The two must agree exactly:
// this one builds the search index, that one builds the query. Any divergence
// means the index holds `kaese` while the query asks for `käse`, and search
// returns nothing with no error anywhere.
//
// Both are asserted against fixtures/normalizer_cases.json. Change the fixtures
// first, then both implementations.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

/** Expanded before accent folding, so `ä` becomes `ae` and not `a`. */
const GERMAN_EXPANSIONS = {
  'ä': 'ae',
  'ö': 'oe',
  'ü': 'ue',
  'ß': 'ss',
};

/** Accents that carry no meaning in German food names. */
const ACCENT_FOLDING = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y',
  'æ': 'ae', 'œ': 'oe',
};

const MIN_MORPHEME_LENGTH = 4;
const MIN_COMPOUND_LENGTH = 9;

/**
 * Folds a string to its searchable form: lowercase, umlauts expanded, accents
 * folded, non-alphanumerics collapsed to single spaces.
 *
 * @param {string} input
 * @returns {string}
 */
export function normalizeGerman(input) {
  if (!input) return '';

  const lower = input.toLowerCase();
  let out = '';

  for (const ch of lower) {
    const expanded = GERMAN_EXPANSIONS[ch];
    if (expanded !== undefined) {
      out += expanded;
      continue;
    }

    const folded = ACCENT_FOLDING[ch];
    if (folded !== undefined) {
      out += folded;
      continue;
    }

    const code = ch.codePointAt(0);
    const isDigit = code >= 0x30 && code <= 0x39;
    const isLetter = code >= 0x61 && code <= 0x7a;
    out += isDigit || isLetter ? ch : ' ';
  }

  return out.trim().replace(/\s+/g, ' ');
}

/**
 * Finds food morphemes inside a German compound word.
 *
 * Takes the longest match at each start position, then advances by one
 * character rather than skipping past the match. Segmenting the word instead
 * (advancing by the match length) would consume "vollkorn" as one piece and
 * never emit "korn", so "Vollkornbrot" would not be findable by "korn" — which
 * is the entire point of doing this.
 *
 * @param {string} token normalized token
 * @param {Set<string>} morphemes
 * @returns {string[]} extra tokens, deduplicated, never the whole token
 */
export function extractCompoundParts(token, morphemes) {
  if (token.length < MIN_COMPOUND_LENGTH) return [];

  const parts = [];
  const seen = new Set();

  for (let start = 0; start + MIN_MORPHEME_LENGTH <= token.length; start++) {
    for (let end = token.length; end >= start + MIN_MORPHEME_LENGTH; end--) {
      const candidate = token.slice(start, end);
      if (!morphemes.has(candidate)) continue;
      if (candidate.length !== token.length && !seen.has(candidate)) {
        seen.add(candidate);
        parts.push(candidate);
      }
      break; // longest match at this position wins
    }
  }

  return parts;
}

/**
 * Builds the text stored in the FTS index for a food.
 *
 * @param {string} name
 * @param {{brand?: string|null, morphemes?: Set<string>}} [options]
 * @returns {string}
 */
export function buildSearchText(name, options = {}) {
  const { brand = null, morphemes = new Set() } = options;

  const normalized = normalizeGerman(brand ? `${name} ${brand}` : name);
  if (!normalized || morphemes.size === 0) return normalized;

  const own = new Set(normalized.split(' '));
  const extra = new Set();
  for (const token of own) {
    for (const part of extractCompoundParts(token, morphemes)) extra.add(part);
  }
  for (const token of own) extra.delete(token);

  return extra.size === 0 ? normalized : `${normalized} ${[...extra].join(' ')}`;
}

/**
 * Loads the morpheme list, skipping comments and blanks.
 *
 * @param {string} [file]
 * @returns {Set<string>}
 */
export function loadMorphemes(file = join(here, 'de_food_morphemes.txt')) {
  return new Set(
    readFileSync(file, 'utf8')
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && !line.startsWith('#')),
  );
}
