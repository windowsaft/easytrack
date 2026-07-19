import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseValue } from './build_bls.mjs';

test('numeric cells pass through', () => {
  assert.equal(parseValue(343), 343);
  assert.equal(parseValue(11.45), 11.45);
  assert.equal(parseValue(0), 0);
});

test('"-" means not determined and must become NULL', () => {
  // The distinction this protects: a food whose fat was never measured must
  // not be displayed as fat-free.
  assert.equal(parseValue('-'), null);
  assert.equal(parseValue(' - '), null);
});

test('blank cells are also not determined', () => {
  assert.equal(parseValue(''), null);
  assert.equal(parseValue('   '), null);
  assert.equal(parseValue(null), null);
  assert.equal(parseValue(undefined), null);
});

test('detection-limit sentinels mean effectively zero', () => {
  assert.equal(parseValue('<LOD'), 0);
  assert.equal(parseValue('<LOQ'), 0);
  assert.equal(parseValue('<LOD or <LOQ'), 0);
  assert.equal(parseValue('TR'), 0);
});

test('zero and not-determined stay distinguishable', () => {
  assert.notEqual(parseValue('-'), parseValue('<LOD'));
  assert.equal(parseValue('<LOD'), 0);
  assert.equal(parseValue('-'), null);
});

test('a decimal comma would still parse, should a release ship one', () => {
  assert.equal(parseValue('11,45'), 11.45);
});

test('unparseable text is treated as unknown rather than zero', () => {
  assert.equal(parseValue('n.v.'), null);
  assert.equal(parseValue('keine Angabe'), null);
});

test('non-finite numbers are rejected', () => {
  assert.equal(parseValue(Number.NaN), null);
  assert.equal(parseValue(Number.POSITIVE_INFINITY), null);
});
