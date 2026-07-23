import 'package:sqlite3/sqlite3.dart';

/// Read-only access to an installed Open Food Facts product pack.
///
/// The sibling of [ReferenceDatabase] for a *downloaded* pack. Same reasoning —
/// a plain `sqlite3` handle, a separate file, replaced wholesale on update — but
/// this one is never bundled: it arrives via the pack installer and lives in the
/// app-support directory. The tables differ from BLS (`off_foods` keyed by
/// barcode), so it is its own class rather than a reuse of [ReferenceDatabase].
class OffPackDatabase {
  OffPackDatabase._(this._db, this.meta);

  final Database _db;

  /// Contents of `pack_meta`: schema version, region, row count, and the ODbL
  /// attribution the licence requires the app to display.
  final Map<String, String> meta;

  /// Pack schema this build understands. A pack declaring a higher version is
  /// refused rather than read with the wrong column expectations.
  static const supportedSchemaVersion = 2;

  Database get raw => _db;

  /// Whether this pack carries the `categories` column (schema v2+). A v1 pack
  /// predates it, so the provider must not SELECT the column and falls back to
  /// name-based drink detection.
  bool get hasCategories =>
      (int.tryParse(meta['schema_version'] ?? '') ?? 0) >= 2;

  int get foodCount => int.tryParse(meta['off_row_count'] ?? '') ?? 0;
  String get region => meta['off_region'] ?? '';
  String get version => meta['off_version'] ?? '';

  /// Attribution required by ODbL. Shown in Settings and on OFF food details.
  String get attribution => meta['off_attribution'] ?? '';

  /// Opens a pack at [path], read-only. Throws if it declares a schema newer
  /// than this build can read — the caller treats that as "not installed" and
  /// prompts for an app update rather than mis-reading columns.
  static OffPackDatabase openAt(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final meta = _readMeta(db);

    final version = int.tryParse(meta['schema_version'] ?? '') ?? 0;
    if (version > supportedSchemaVersion) {
      db.close();
      throw StateError(
        'Product pack schema $version is newer than the supported '
        '$supportedSchemaVersion. Update the app or rebuild the pack.',
      );
    }

    return OffPackDatabase._(db, meta);
  }

  static Map<String, String> _readMeta(Database db) {
    final rows = db.select('SELECT key, value FROM pack_meta');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  void dispose() => _db.close();
}
