import 'package:sqlite3/sqlite3.dart';

/// Writes a small but real Open Food Facts pack to [path], matching the schema
/// build_off.mjs produces. Used across the pack tests so none of them depend on
/// the ETL having run.
void writeOffPack(
  String path, {
  int schemaVersion = 2,
  String region = 'dach',
  String version = '2026-07-20',
}) {
  final db = sqlite3.open(path);
  try {
    db.execute('''
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
  categories         TEXT
);
CREATE VIRTUAL TABLE off_fts USING fts5(
  search_text, content='off_foods', content_rowid='id',
  tokenize='unicode61 remove_diacritics 0'
);
CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
''');

    final insert = db.prepare('''
      INSERT INTO off_foods
        (barcode, name, brands, search_text, serving_size_g, kcal,
         protein_g, carbs_g, fat_g, sugar_g, sat_fat_g, salt_g, fiber_g,
         completeness_score, categories)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');

    // search_text is pre-normalized the way normalizeGerman would fold it.
    // Coca-Cola carries beverage tags so drink detection has a real signal to
    // read; the spread does not, and must stay grams.
    insert.execute([
      '5449000000996',
      'Coca-Cola',
      'Coca-Cola',
      'coca cola',
      250.0,
      42.0,
      0.0,
      10.6,
      0.0,
      10.6,
      0.0,
      0.0,
      0.0,
      0.9,
      'en:beverages en:carbonated-drinks en:sodas en:colas',
    ]);
    insert.execute([
      '3017620422003',
      'Nuss-Nougat-Creme',
      'Ferrero, Nutella',
      'nuss nougat creme ferrero nutella',
      15.0,
      539.0,
      6.3,
      57.5,
      30.9,
      56.3,
      10.6,
      0.107,
      null,
      0.95,
      'en:spreads en:sweet-spreads en:hazelnut-spreads',
    ]);
    insert.close();

    db.execute("INSERT INTO off_fts(off_fts) VALUES('rebuild')");

    final meta = db.prepare('INSERT INTO pack_meta (key, value) VALUES (?, ?)');
    for (final entry in {
      'schema_version': '$schemaVersion',
      'off_region': region,
      'off_version': version,
      'off_row_count': '2',
      'off_license': 'Open Database License (ODbL) v1.0',
      'off_attribution':
          'Open Food Facts contributors, https://openfoodfacts.org — '
          'Open Database License (ODbL) v1.0',
      'off_source': 'https://openfoodfacts.org',
      'built_at': '2026-07-20T00:00:00.000Z',
    }.entries) {
      meta.execute([entry.key, entry.value]);
    }
    meta.close();
  } finally {
    db.close();
  }
}
