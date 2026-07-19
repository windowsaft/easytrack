// Node half of the normalizer parity check. Run with: node --test tools/etl/
//
// The Dart half lives in test/core/german_normalizer_test.dart and reads the
// same fixture file. Both must pass for search to work.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  buildSearchText,
  extractCompoundParts,
  loadMorphemes,
  normalizeGerman,
} from './normalize.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = JSON.parse(
  readFileSync(join(here, 'fixtures', 'normalizer_cases.json'), 'utf8'),
);
const morphemes = loadMorphemes();

test('normalizeGerman matches the shared fixtures', () => {
  for (const [input, expected] of fixtures.normalize) {
    assert.equal(
      normalizeGerman(input),
      expected,
      `normalizeGerman(${JSON.stringify(input)})`,
    );
  }
});

test('normalizeGerman output contains only a-z, 0-9 and single spaces', () => {
  for (const [input] of fixtures.normalize) {
    const out = normalizeGerman(input);
    assert.match(out, /^$|^[a-z0-9]+( [a-z0-9]+)*$/, `input: ${input}`);
  }
});

test('normalizeGerman is idempotent', () => {
  for (const [input] of fixtures.normalize) {
    const once = normalizeGerman(input);
    assert.equal(normalizeGerman(once), once, `input: ${input}`);
  }
});

test('extractCompoundParts matches the shared fixtures', () => {
  for (const [token, expected] of fixtures.compounds) {
    assert.deepEqual(
      extractCompoundParts(token, morphemes),
      expected,
      `extractCompoundParts(${JSON.stringify(token)})`,
    );
  }
});

test('buildSearchText matches the shared fixtures', () => {
  for (const { name, brand, expected } of fixtures.searchText) {
    assert.equal(
      buildSearchText(name, { brand, morphemes }),
      expected,
      `buildSearchText(${JSON.stringify(name)})`,
    );
  }
});

test('morpheme list has no duplicate entries', () => {
  const raw = readFileSync(join(here, 'de_food_morphemes.txt'), 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith('#'));

  const duplicates = raw.filter((v, i) => raw.indexOf(v) !== i);
  assert.deepEqual(duplicates, [], 'duplicate morphemes');
});

test('morpheme list is normalized and long enough to be useful', () => {
  for (const morpheme of morphemes) {
    assert.equal(
      normalizeGerman(morpheme),
      morpheme,
      `morpheme "${morpheme}" is not in normalized form`,
    );
    assert.ok(
      morpheme.length >= 4,
      `morpheme "${morpheme}" is shorter than 4 characters`,
    );
  }
});
