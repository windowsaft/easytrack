import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Read-only access to the bundled food reference data.
///
/// Deliberately a plain `sqlite3` handle rather than a Drift database, and
/// deliberately a separate file from the user database:
///
/// - The pack is generated, versioned and replaced wholesale. Giving it Drift
///   migrations would mean migrating data that is simply rebuilt upstream.
/// - Keeping it out of the user database is what makes replacement safe. A
///   food-data update is a file swap, never a migration over diary history.
/// - `ATTACH`-ing the two would allow joins, but would also pin the file open
///   during a swap and break the future web target. Diary entries snapshot
///   their nutrients precisely so no cross-database join is needed.
class ReferenceDatabase {
  ReferenceDatabase._(this._db, this.meta);

  final Database _db;

  /// Contents of `pack_meta`, including the schema version and the attribution
  /// text the licence requires the app to display.
  final Map<String, String> meta;

  /// Pack schema this build of the app understands.
  ///
  /// A pack declaring a higher version is refused rather than read with the
  /// wrong column expectations.
  static const supportedSchemaVersion = 1;

  static const _assetPath = 'assets/data/bls.sqlite';
  static const _fileName = 'bls.sqlite';

  Database get raw => _db;

  int get foodCount => int.parse(meta['bls_row_count'] ?? '0');

  /// Attribution required by CC BY 4.0. Shown in Settings and on food details.
  String get blsCitation => meta['bls_citation'] ?? '';

  /// Copies the bundled pack out of the app bundle on first run and opens it.
  ///
  /// SQLite cannot read directly from a Flutter asset, so the file has to exist
  /// on disk. It is re-copied whenever the bundled asset is a different size,
  /// which is how a pack refreshed by an app update reaches an existing install.
  static Future<ReferenceDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _fileName));

    final asset = await rootBundle.load(_assetPath);
    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );

    if (!file.existsSync() || await file.length() != bytes.length) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    return openAt(file.path);
  }

  /// Opens a pack at an explicit path. Used by tests and by the future
  /// downloaded product packs.
  static ReferenceDatabase openAt(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final meta = _readMeta(db);

    final version = int.tryParse(meta['schema_version'] ?? '') ?? 0;
    if (version > supportedSchemaVersion) {
      db.close();
      throw StateError(
        'Reference pack schema $version is newer than the supported '
        '$supportedSchemaVersion. Update the app or rebuild the pack.',
      );
    }

    return ReferenceDatabase._(db, meta);
  }

  static Map<String, String> _readMeta(Database db) {
    final rows = db.select('SELECT key, value FROM pack_meta');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  void dispose() => _db.close();
}
