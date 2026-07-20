import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import Database from 'better-sqlite3';

import { buildPack, isValidProduct } from './build_off.mjs';

const seedPath = fileURLToPath(new URL('./off_seed.json', import.meta.url));

describe('isValidProduct', () => {
  const base = { name: 'Test', kcal: 100, protein_g: 5, carbs_g: 10, fat_g: 3 };

  test('accepts a complete, plausible product', () => {
    assert.equal(isValidProduct(base), true);
  });

  test('rejects a missing core macro', () => {
    assert.equal(isValidProduct({ ...base, protein_g: null }), false);
  });

  test('rejects impossible calories', () => {
    assert.equal(isValidProduct({ ...base, kcal: 999 }), false);
  });

  test('rejects a macro sum over 105 g', () => {
    assert.equal(
      isValidProduct({ ...base, protein_g: 60, carbs_g: 60, fat_g: 20 }),
      false,
    );
  });

  test('rejects a one-character name', () => {
    assert.equal(isValidProduct({ ...base, name: 'X' }), false);
  });
});

describe('buildPack', () => {
  let dir;
  let outPath;
  let db;

  before(async () => {
    dir = await mkdtemp(join(tmpdir(), 'off-pack-'));
    outPath = join(dir, 'off_dach.sqlite');
    const seed = JSON.parse(await readFile(seedPath, 'utf8'));
    const { rowCount, skipped } = await buildPack({
      products: seed.products,
      region: 'dach',
      version: '2026-07-20',
      outPath,
    });
    // 20 valid, 4 invalid in the seed.
    assert.equal(rowCount, 20);
    assert.equal(skipped, 4);
    db = new Database(outPath, { readonly: true });
  });

  after(async () => {
    db?.close();
    await rm(dir, { recursive: true, force: true });
  });

  test('writes exactly the valid products', () => {
    const count = db.prepare('SELECT COUNT(*) c FROM off_foods').get().c;
    assert.equal(count, 20);
  });

  test('drops the sanity-filtered rows', () => {
    const junk = db
      .prepare("SELECT COUNT(*) c FROM off_foods WHERE barcode LIKE '00000000%'")
      .get().c;
    assert.equal(junk, 0);
  });

  test('every stored food has calories and a search text', () => {
    const bad = db
      .prepare(
        `SELECT COUNT(*) c FROM off_foods
         WHERE kcal IS NULL OR search_text IS NULL OR TRIM(search_text) = ''`,
      )
      .get().c;
    assert.equal(bad, 0);
  });

  test('is searchable by German-normalized brand and name', () => {
    const hits = db
      .prepare(
        `SELECT f.name FROM off_fts
         JOIN off_foods f ON f.id = off_fts.rowid
         WHERE off_fts MATCH ? ORDER BY bm25(off_fts)`,
      )
      .all('"nutella"');
    assert.ok(hits.some((r) => r.name.includes('Nuss-Nougat')));
  });

  test('resolves a barcode to a product', () => {
    const row = db
      .prepare('SELECT name FROM off_foods WHERE barcode = ?')
      .get('5449000000996');
    assert.equal(row.name, 'Coca-Cola');
  });

  test('carries the ODbL attribution the licence requires', () => {
    const meta = Object.fromEntries(
      db.prepare('SELECT key, value FROM pack_meta').all().map((r) => [r.key, r.value]),
    );
    assert.equal(meta.schema_version, '1');
    assert.equal(meta.off_region, 'dach');
    assert.match(meta.off_license, /ODbL/);
    assert.match(meta.off_attribution, /Open Food Facts/);
    assert.equal(meta.off_row_count, '20');
  });
});
