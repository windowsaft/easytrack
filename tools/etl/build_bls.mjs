// Builds the bundled BLS reference database.
//
//   node tools/etl/build_bls.mjs [--zip <path>] [--out <path>]
//
// Reads the Bundeslebensmittelschlüssel 4.0 distribution and emits a SQLite
// file with one row per food plus an FTS5 index over the normalized search
// text. The output ships inside the APK — it is ~3 MB and is the primary
// search source, so the app is fully usable offline the moment it installs.
//
// The file format is documented in docs/bls-format.md. The part that matters
// here: missing values are sentinel STRINGS inside the value column, not blank
// cells, and "-" (not determined) must become NULL while the detection-limit
// sentinels become 0. Conflating them would render an unmeasured food as
// fat-free.

import { createWriteStream } from 'node:fs';
import { mkdir, rm, stat } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

import Database from 'better-sqlite3';
import ExcelJS from 'exceljs';
import { open as openZip } from 'yauzl-promise';

import { buildSearchText, loadMorphemes, normalizeGerman } from './normalize.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');

const BLS_URL = 'https://blsdb.de/assets/uploads/BLS_4_0_2025_DE.zip';
const CACHE_DIR = join(here, '.cache');
const DEFAULT_OUT = join(repoRoot, 'assets', 'data', 'bls.sqlite');

/** Schema version of the reference pack. The app refuses a pack it cannot read. */
const PACK_SCHEMA_VERSION = 1;

/**
 * The BLS components surfaced in the app, keyed by INFOODS tagname.
 *
 * 28 of 138. The remaining 110 roughly triple the table for nutrients the app
 * has no screen for; they can be added when a micronutrient view exists.
 */
const COMPONENTS = {
  ENERCC: 'kcal',
  ENERCJ: 'kj',
  PROT625: 'protein_g',
  FAT: 'fat_g',
  CHO: 'carbs_g',
  SUGAR: 'sugar_g',
  STARCH: 'starch_g',
  FIBT: 'fiber_g',
  FASAT: 'sat_fat_g',
  FAMS: 'mufa_g',
  FAPU: 'pufa_g',
  CHORL: 'cholesterol_mg',
  NACL: 'salt_g',
  NA: 'sodium_mg',
  K: 'potassium_mg',
  CA: 'calcium_mg',
  MG: 'magnesium_mg',
  FE: 'iron_mg',
  ZN: 'zinc_mg',
  VITA: 'vit_a_ug',
  VITC: 'vit_c_mg',
  VITD: 'vit_d_ug',
  VITE: 'vit_e_mg',
  VITB12: 'vit_b12_ug',
  FOL: 'folate_ug',
  WATER: 'water_g',
  ALC: 'alcohol_g',
};

/**
 * Sentinels meaning "measured, but below the reporting threshold".
 *
 * These become 0: the substance is effectively absent. Distinct from "-",
 * which means nobody measured it and must stay NULL.
 */
const BELOW_THRESHOLD = new Set(['<LOD', '<LOQ', '<LOD or <LOQ', 'TR']);

/** German food-group names, keyed by the first letter of the BLS code. */
const FOOD_GROUPS = {
  B: 'Brot',
  C: 'Getreide',
  D: 'Backwaren',
  E: 'Teigwaren',
  F: 'Obst',
  G: 'Gemüse',
  H: 'Pilze & Sprossen',
  K: 'Stärke & Bindemittel',
  M: 'Milch & Käse',
  N: 'Kaffee & Tee',
  P: 'Alkoholische Getränke',
  Q: 'Öle & Fette',
  R: 'Gewürze & Salz',
  S: 'Süßwaren & Zucker',
  T: 'Fisch & Meeresfrüchte',
  U: 'Schweinefleisch',
  V: 'Fleisch',
  W: 'Wurst & Speck',
  X: 'Gerichte',
  Y: 'Suppen & Brühen',
};

/**
 * Converts one BLS cell to a number, NULL, or 0.
 *
 * @param {unknown} raw
 * @returns {number|null}
 */
export function parseValue(raw) {
  if (typeof raw === 'number') return Number.isFinite(raw) ? raw : null;
  if (raw === null || raw === undefined) return null;

  const text = String(raw).trim();
  if (text === '' || text === '-') return null;
  if (BELOW_THRESHOLD.has(text)) return 0;

  // Defensive: a future revision could ship a decimal comma.
  const numeric = Number(text.replace(',', '.'));
  return Number.isFinite(numeric) ? numeric : null;
}

async function fileExists(path) {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

/** Downloads the distribution once and caches it. */
async function ensureZip() {
  const target = join(CACHE_DIR, 'BLS_4_0_2025_DE.zip');
  if (await fileExists(target)) {
    console.log(`using cached ${target}`);
    return target;
  }

  await mkdir(CACHE_DIR, { recursive: true });
  console.log(`downloading ${BLS_URL} ...`);
  const response = await fetch(BLS_URL);
  if (!response.ok) {
    throw new Error(`download failed: HTTP ${response.status}`);
  }
  await pipeline(response.body, createWriteStream(target));
  console.log(`saved ${target}`);
  return target;
}

/** Extracts the two workbooks we need into the cache directory. */
async function extractWorkbooks(zipPath) {
  const wanted = {
    'BLS_4_0_Daten_2025_DE.xlsx': join(CACHE_DIR, 'data.xlsx'),
    'BLS_4_0_Components_DE_EN.xlsx': join(CACHE_DIR, 'components.xlsx'),
  };

  const missing = [];
  for (const target of Object.values(wanted)) {
    if (!(await fileExists(target))) missing.push(target);
  }
  if (missing.length === 0) {
    console.log('using cached workbooks');
    return wanted;
  }

  const zip = await openZip(zipPath);
  try {
    for await (const entry of zip) {
      const base = entry.filename.split('/').pop();
      const target = wanted[base];
      if (!target) continue;
      const readStream = await entry.openReadStream();
      await pipeline(readStream, createWriteStream(target));
      console.log(`extracted ${base}`);
    }
  } finally {
    await zip.close();
  }
  return wanted;
}

/** Reads the component legend, so units and names come from the data itself. */
async function readComponents(path) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(path);
  const sheet = workbook.worksheets[0];

  const byCode = new Map();
  for (let row = 2; row <= sheet.rowCount; row++) {
    const code = String(sheet.getRow(row).getCell(2).value ?? '').trim();
    if (!code) continue;
    byCode.set(code, {
      nameDe: String(sheet.getRow(row).getCell(3).value ?? '').trim(),
      unit: String(sheet.getRow(row).getCell(5).value ?? '').trim(),
    });
  }
  return byCode;
}

function createSchema(db) {
  const columns = Object.values(COMPONENTS)
    .map((name) => `  ${name} REAL`)
    .join(',\n');

  db.exec(`
CREATE TABLE bls_foods (
  id          INTEGER PRIMARY KEY,
  bls_code    TEXT NOT NULL UNIQUE,
  name_de     TEXT NOT NULL,
  name_en     TEXT,
  food_group  TEXT,
  search_text TEXT NOT NULL,
${columns}
);

-- External-content FTS: the text lives in bls_foods, so it is not stored twice.
CREATE VIRTUAL TABLE bls_fts USING fts5(
  search_text,
  content='bls_foods',
  content_rowid='id',
  tokenize='unicode61 remove_diacritics 0'
);

CREATE TABLE pack_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`);
}

async function build({ zipPath, outPath }) {
  const zip = zipPath ?? (await ensureZip());
  const workbooks = await extractWorkbooks(zip);

  const components = await readComponents(workbooks['BLS_4_0_Components_DE_EN.xlsx']);
  console.log(`component legend: ${components.size} entries`);

  const morphemes = loadMorphemes();
  console.log(`morphemes: ${morphemes.size}`);

  await mkdir(dirname(outPath), { recursive: true });
  await rm(outPath, { force: true });
  const db = new Database(outPath);
  db.pragma('journal_mode = DELETE'); // no -wal file alongside a shipped asset
  createSchema(db);

  const targetColumns = Object.values(COMPONENTS);
  const insert = db.prepare(`
    INSERT INTO bls_foods
      (bls_code, name_de, name_en, food_group, search_text, ${targetColumns.join(', ')})
    VALUES
      (@bls_code, @name_de, @name_en, @food_group, @search_text, ${targetColumns
        .map((c) => `@${c}`)
        .join(', ')})
  `);

  const reader = new ExcelJS.stream.xlsx.WorkbookReader(
    workbooks['BLS_4_0_Daten_2025_DE.xlsx'],
    { entries: 'emit', sharedStrings: 'cache', worksheets: 'emit' },
  );

  /** @type {Record<string, number>} component code -> value column index */
  let valueColumn = null;
  let rows = 0;
  const missingCounts = Object.fromEntries(targetColumns.map((c) => [c, 0]));

  const insertMany = db.transaction((records) => {
    for (const record of records) insert.run(record);
  });
  const batch = [];

  for await (const sheet of reader) {
    for await (const row of sheet) {
      const cells = [];
      row.eachCell({ includeEmpty: true }, (cell, col) => {
        cells[col] = cell.value;
      });

      // Header: map component code -> column. Positions are derived from the
      // captions rather than assumed, so a reordered release still works.
      if (valueColumn === null) {
        valueColumn = {};
        for (let col = 4; col <= 417; col += 3) {
          const code = String(cells[col] ?? '').split(' ')[0];
          if (code) valueColumn[code] = col;
        }

        const absent = Object.keys(COMPONENTS).filter((c) => !(c in valueColumn));
        if (absent.length > 0) {
          throw new Error(
            `BLS file is missing expected components: ${absent.join(', ')}. ` +
              'The distribution layout changed; re-check docs/bls-format.md.',
          );
        }
        continue;
      }

      const blsCode = String(cells[1] ?? '').trim();
      const nameDe = String(cells[2] ?? '').trim();
      if (!blsCode || !nameDe) continue;

      const record = {
        bls_code: blsCode,
        name_de: nameDe,
        name_en: String(cells[3] ?? '').trim() || null,
        food_group: FOOD_GROUPS[blsCode[0]] ?? null,
        search_text: buildSearchText(nameDe, { morphemes }),
      };

      for (const [code, column] of Object.entries(COMPONENTS)) {
        const value = parseValue(cells[valueColumn[code]]);
        record[column] = value;
        if (value === null) missingCounts[column]++;
      }

      batch.push(record);
      rows++;

      if (batch.length >= 1000) {
        insertMany(batch);
        batch.length = 0;
      }
    }
  }
  if (batch.length > 0) insertMany(batch);

  // Populate the external-content index and compact it into one b-tree.
  db.exec("INSERT INTO bls_fts(bls_fts) VALUES('rebuild')");
  db.exec("INSERT INTO bls_fts(bls_fts) VALUES('optimize')");

  const meta = db.prepare('INSERT INTO pack_meta (key, value) VALUES (?, ?)');
  const setMeta = db.transaction((entries) => {
    for (const [key, value] of entries) meta.run(key, String(value));
  });
  setMeta([
    ['schema_version', PACK_SCHEMA_VERSION],
    ['bls_version', '4.0'],
    ['bls_source', BLS_URL],
    ['bls_license', 'CC BY 4.0'],
    [
      'bls_citation',
      'Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), ' +
        'Version 4.0 – Deutsche Nährstoffdatenbank. Karlsruhe. ' +
        'DOI: 10.25826/Data20251217-134202-0',
    ],
    ['bls_row_count', rows],
    ['built_at', new Date().toISOString()],
  ]);

  db.exec('VACUUM');
  db.close();

  const { size } = await stat(outPath);
  console.log(`\nwrote ${outPath}`);
  console.log(`  foods: ${rows}`);
  console.log(`  size:  ${(size / 1024 / 1024).toFixed(2)} MB`);

  const notable = Object.entries(missingCounts)
    .filter(([, n]) => n > 0)
    .sort((a, b) => b[1] - a[1]);
  if (notable.length > 0) {
    console.log('  nutrients with missing values (NULL, not zero):');
    for (const [column, n] of notable) {
      console.log(
        `    ${column.padEnd(16)} ${String(n).padStart(5)} / ${rows}` +
          `  (${((100 * n) / rows).toFixed(1)}%)`,
      );
    }
  }

  if (rows < 7000) {
    throw new Error(`only ${rows} foods imported; expected about 7140`);
  }
}

function parseArgs(argv) {
  const args = { zipPath: null, outPath: DEFAULT_OUT };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--zip') args.zipPath = resolve(argv[++i]);
    else if (argv[i] === '--out') args.outPath = resolve(argv[++i]);
  }
  return args;
}

// Only run when invoked directly, so the helpers stay unit-testable.
// pathToFileURL rather than string-building the URL: on Windows a drive path
// becomes file:///C:/... with three slashes, and hand-rolling it silently
// never matches, leaving the script to exit having done nothing.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  build(parseArgs(process.argv.slice(2))).catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

export { build, COMPONENTS, FOOD_GROUPS };
