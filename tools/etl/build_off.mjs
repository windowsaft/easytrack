// Builds an Open Food Facts product pack and its release manifest.
//
//   node tools/etl/build_off.mjs [--region dach] [--seed off_seed.json]
//                                [--base-url <url>] [--version <id>]
//
// Unlike the BLS pack, the OFF pack is NOT bundled in the APK — it is downloaded
// on first run and refreshed monthly, so the food data can change without
// shipping a new app. This script produces the artifact the installer fetches:
// an off_<region>.sqlite file plus an entry in dist/manifest.json carrying its
// size, SHA-256 and row count.
//
// Two ways to feed it, same writer and schema either way:
//   - PRODUCTION: run build_off.sql with the DuckDB CLI against the HuggingFace
//     food.parquet dump to emit rows, then hand them here. See build_off.sql.
//   - LOCAL/DEV (this default): read off_seed.json, a small set of real branded
//     products, so the whole download → verify → install path can be exercised
//     end to end without the 0.9 GB dump or DuckDB installed.
//
// The pack file is byte-for-byte what the app verifies against the manifest, so
// the manifest is written from the finished file, never from the pre-write plan.

import { createHash } from 'node:crypto';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import Database from 'better-sqlite3';

import { buildSearchText, loadMorphemes } from './normalize.mjs';

const here = dirname(fileURLToPath(import.meta.url));

/** Schema version of the product pack. The app refuses a pack it cannot read.
 *
 * v2 adds the `categories` column (space-joined Open Food Facts category tags),
 * which the app uses for robust drink detection — a Coca-Cola is a beverage
 * because its tags say `en:sodas`, not because its name happens to contain a
 * keyword. A v1 pack (no column) still installs; the app falls back to name
 * detection for it. */
const PACK_SCHEMA_VERSION = 2;

/** Schema version of manifest.json itself. */
const MANIFEST_SCHEMA_VERSION = 1;

const REGIONS = new Set(['de', 'dach', 'world']);

const DEFAULT_SEED = join(here, 'off_seed.json');
const DIST_DIR = join(here, 'dist');

// Placeholder release base. In production this is the GitHub Release the monthly
// cron publishes to; for local end-to-end testing, pass e.g.
//   --base-url http://localhost:8000
// and serve dist/ with `python -m http.server 8000`.
const DEFAULT_BASE_URL = 'https://REPLACE_ME.example/easytrack-packs/off-latest';

const ODBL =
  'Open Food Facts contributors, https://openfoodfacts.org — ' +
  'Open Database License (ODbL) v1.0';

/**
 * Whether a product survives the sanity filter.
 *
 * Mirrors the WHERE clause in build_off.sql so the seed pack and the real pack
 * are the same shape: the four core macros must be present, calories must be
 * physically possible (nothing beats pure fat at ~900 kcal), the macro sum must
 * fit inside 100 g of food with a little slack for rounding, and the name has to
 * be more than a stray character.
 *
 * @param {Record<string, unknown>} p
 * @returns {boolean}
 */
export function isValidProduct(p) {
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const name = typeof p.name === 'string' ? p.name.trim() : '';
  const kcal = num(p.kcal);
  const protein = num(p.protein_g);
  const carbs = num(p.carbs_g);
  const fat = num(p.fat_g);

  if (name.length < 2) return false;
  if (kcal === null || protein === null || carbs === null || fat === null) {
    return false;
  }
  if (kcal < 0 || kcal > 950) return false;
  if (protein + carbs + fat > 105) return false;
  return true;
}

function createSchema(db) {
  db.exec(`
CREATE TABLE off_foods (
  id                 INTEGER PRIMARY KEY,
  barcode            TEXT NOT NULL UNIQUE,
  name               TEXT NOT NULL,
  brands             TEXT,
  search_text        TEXT NOT NULL,
  serving_size_g     REAL,
  kcal               REAL NOT NULL,
  protein_g          REAL,
  carbs_g            REAL,
  fat_g              REAL,
  sugar_g            REAL,
  sat_fat_g          REAL,
  salt_g             REAL,
  fiber_g            REAL,
  completeness_score REAL,
  -- Space-joined Open Food Facts category tags (e.g. "en:sodas en:beverages"),
  -- or NULL when the source has none. Read on device for drink detection.
  categories         TEXT
);

-- External-content FTS: the text lives in off_foods, so it is not stored twice.
CREATE VIRTUAL TABLE off_fts USING fts5(
  search_text,
  content='off_foods',
  content_rowid='id',
  tokenize='unicode61 remove_diacritics 0'
);

CREATE TABLE pack_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`);
}

/**
 * Writes a pack file from already-loaded product rows and returns its stats.
 *
 * @param {object} args
 * @param {Array<Record<string, unknown>>} args.products
 * @param {string} args.region
 * @param {string} args.version
 * @param {string} args.outPath
 * @param {Set<string>} [args.morphemes]
 * @returns {Promise<{ rowCount: number, skipped: number }>}
 */
export async function buildPack({ products, region, version, outPath, morphemes }) {
  const morphs = morphemes ?? loadMorphemes();

  await mkdir(dirname(outPath), { recursive: true });
  await rm(outPath, { force: true });
  const db = new Database(outPath);
  db.pragma('journal_mode = DELETE'); // no -wal file alongside the shipped pack
  createSchema(db);

  const insert = db.prepare(`
    INSERT OR IGNORE INTO off_foods
      (barcode, name, brands, search_text, serving_size_g,
       kcal, protein_g, carbs_g, fat_g, sugar_g, sat_fat_g, salt_g, fiber_g,
       completeness_score, categories)
    VALUES
      (@barcode, @name, @brands, @search_text, @serving_size_g,
       @kcal, @protein_g, @carbs_g, @fat_g, @sugar_g, @sat_fat_g, @salt_g,
       @fiber_g, @completeness_score, @categories)
  `);

  let rowCount = 0;
  let skipped = 0;
  const opt = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

  const insertMany = db.transaction((rows) => {
    for (const p of rows) {
      if (!isValidProduct(p)) {
        skipped++;
        continue;
      }
      const name = String(p.name).trim();
      const brands = p.brands ? String(p.brands).trim() : null;
      // Category tags arrive as an array from DuckDB; the seed has none. Store
      // them space-joined (tags never break a needle across the space) or NULL.
      const cats = Array.isArray(p.categories_tags)
        ? p.categories_tags.map((t) => String(t).trim()).filter(Boolean).join(' ')
        : typeof p.categories_tags === 'string'
          ? p.categories_tags.trim()
          : '';
      const info = insert.run({
        barcode: String(p.barcode).trim(),
        name,
        brands,
        search_text: buildSearchText(name, { brand: brands, morphemes: morphs }),
        serving_size_g: opt(p.serving_size_g),
        kcal: opt(p.kcal),
        protein_g: opt(p.protein_g),
        carbs_g: opt(p.carbs_g),
        fat_g: opt(p.fat_g),
        sugar_g: opt(p.sugar_g),
        sat_fat_g: opt(p.sat_fat_g),
        salt_g: opt(p.salt_g),
        fiber_g: opt(p.fiber_g),
        completeness_score: opt(p.completeness_score),
        categories: cats.length > 0 ? cats : null,
      });
      if (info.changes > 0) rowCount++;
      else skipped++; // duplicate barcode ignored
    }
  });
  insertMany(products);

  db.exec("INSERT INTO off_fts(off_fts) VALUES('rebuild')");
  db.exec("INSERT INTO off_fts(off_fts) VALUES('optimize')");

  const meta = db.prepare('INSERT INTO pack_meta (key, value) VALUES (?, ?)');
  const setMeta = db.transaction((entries) => {
    for (const [key, value] of entries) meta.run(key, String(value));
  });
  setMeta([
    ['schema_version', PACK_SCHEMA_VERSION],
    ['off_region', region],
    ['off_version', version],
    ['off_row_count', rowCount],
    ['off_license', 'Open Database License (ODbL) v1.0'],
    ['off_attribution', ODBL],
    ['off_source', 'https://openfoodfacts.org'],
    ['built_at', new Date().toISOString()],
  ]);

  db.exec('VACUUM');
  db.close();

  return { rowCount, skipped };
}

async function sha256Of(path) {
  const bytes = await readFile(path);
  return createHash('sha256').update(bytes).digest('hex');
}

/**
 * Merges one region's release into manifest.json, creating it if absent, so
 * building de / dach / world in turn accumulates into a single manifest.
 */
async function updateManifest({ manifestPath, region, release }) {
  let manifest = { schemaVersion: MANIFEST_SCHEMA_VERSION, packs: {} };
  try {
    const existing = JSON.parse(await readFile(manifestPath, 'utf8'));
    if (existing && typeof existing === 'object' && existing.packs) {
      manifest = existing;
    }
  } catch {
    // No manifest yet; start fresh.
  }
  manifest.schemaVersion = MANIFEST_SCHEMA_VERSION;
  manifest.packs[region] = release;
  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

async function build({ seedPath, region, version, baseUrl, outPath, manifestPath }) {
  const seed = JSON.parse(await readFile(seedPath, 'utf8'));
  const products = Array.isArray(seed) ? seed : seed.products;
  if (!Array.isArray(products)) {
    throw new Error(`seed ${seedPath} has no products array`);
  }

  const { rowCount, skipped } = await buildPack({
    products,
    region,
    version,
    outPath,
  });

  const { size } = await stat(outPath);
  const sha256 = await sha256Of(outPath);
  const url = `${baseUrl.replace(/\/$/, '')}/off_${region}.sqlite`;

  const release = {
    version,
    url,
    bytes: size,
    sha256,
    rowCount,
    minAppSchema: PACK_SCHEMA_VERSION,
  };
  await updateManifest({ manifestPath, region, release });

  console.log(`\nwrote ${outPath}`);
  console.log(`  region:  ${region}`);
  console.log(`  foods:   ${rowCount} (${skipped} skipped by the sanity filter)`);
  console.log(`  size:    ${(size / 1024).toFixed(1)} KB`);
  console.log(`  sha256:  ${sha256}`);
  console.log(`  url:     ${url}`);
  console.log(`  manifest ${manifestPath}`);

  if (url.includes('REPLACE_ME')) {
    console.log(
      '\nNote: the URL is a placeholder. Pass --base-url to point at your ' +
        'GitHub Release (production) or a local server such as ' +
        'http://localhost:8000 (dev).',
    );
  }
}

function parseArgs(argv) {
  const args = {
    seedPath: DEFAULT_SEED,
    region: 'dach',
    version: new Date().toISOString().slice(0, 10),
    baseUrl: DEFAULT_BASE_URL,
    outPath: null,
    manifestPath: join(DIST_DIR, 'manifest.json'),
  };
  for (let i = 0; i < argv.length; i++) {
    const next = () => argv[++i];
    switch (argv[i]) {
      case '--seed':
        args.seedPath = resolve(next());
        break;
      case '--region':
        args.region = next();
        break;
      case '--version':
        args.version = next();
        break;
      case '--base-url':
        args.baseUrl = next();
        break;
      case '--out':
        args.outPath = resolve(next());
        break;
      case '--manifest':
        args.manifestPath = resolve(next());
        break;
    }
  }
  if (!REGIONS.has(args.region)) {
    throw new Error(`unknown region "${args.region}"; expected one of ${[...REGIONS].join(', ')}`);
  }
  args.outPath ??= join(DIST_DIR, `off_${args.region}.sqlite`);
  return args;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  build(parseArgs(process.argv.slice(2))).catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

export { build, PACK_SCHEMA_VERSION, MANIFEST_SCHEMA_VERSION };
