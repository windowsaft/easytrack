import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../db/user_database.dart';

/// Thrown when a picked file is not a valid EasyTrack backup, or is one this
/// build is too old to read. Import stages to a side file and only swaps the
/// live database on success, so throwing here always leaves the current data
/// untouched — the same guarantee the product-pack installer makes.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

/// What a verified, staged backup contains — shown to the user before they
/// confirm the (destructive) restore.
class BackupInfo {
  const BackupInfo({
    required this.appVersion,
    required this.createdAt,
    required this.entryCount,
  });

  /// The app build that wrote the backup, e.g. `1.0.0+1`, or null if unstated.
  final String? appVersion;

  /// When the backup was created (UTC), or null if unparseable.
  final DateTime? createdAt;

  /// Live diary entries in the backup — a human-meaningful measure of its size.
  final int entryCount;
}

/// Exports and imports the whole user database as a single zip.
///
/// A backup is `user.sqlite` (a clean [VACUUM INTO] snapshot) plus a small JSON
/// manifest describing the build and schema it came from. Bundling the raw
/// database — rather than serialising each table — keeps every row, its sync
/// bookkeeping (see [SyncableTable]) and soft-delete tombstones intact, and
/// automatically covers any table a future schema adds.
///
/// Import cannot overwrite `user.sqlite` while a connection holds it, so it is a
/// two-step dance: [stageImport] verifies the zip and writes the database beside
/// the live one as `user.sqlite.import`; [applyPendingImport] — run at boot,
/// with no database open — swaps it into place. See `app_boot.dart` for the
/// restart that bridges the two.
class BackupService {
  BackupService({
    required this.db,
    required this.documentsDirectory,
    required this.temporaryDirectory,
    required this.appVersion,
    required this.schemaVersion,
  });

  final UserDatabase db;

  /// Where `user.sqlite` lives — drift_flutter's application-documents dir.
  final Future<Directory> Function() documentsDirectory;
  final Future<Directory> Function() temporaryDirectory;

  /// This build's version+build, recorded in the manifest.
  final String appVersion;

  /// This build's drift schema version, used to reject a backup from a newer
  /// app that this build could not migrate.
  final int schemaVersion;

  /// The live database's filename, as opened by `driftDatabase(name: 'user')`.
  static const dbFileName = 'user.sqlite';

  /// The staged import, waiting for the next boot to swap it in.
  static const stagedFileName = 'user.sqlite.import';

  static const _manifestName = 'backup.json';
  static const _dbEntryName = 'user.sqlite';
  static const _formatId = 'easytrack-backup';
  static const _formatVersion = 1;

  // --- Export ------------------------------------------------------------

  /// Builds a backup zip in the temp directory and returns it, ready to hand to
  /// the share sheet. The caller owns the returned file.
  Future<File> exportToZip() async {
    final tmp = await temporaryDirectory();

    // VACUUM INTO writes a single, fully checkpointed copy — correct even though
    // the live database runs in WAL mode (a plain file copy could miss committed
    // frames still in the -wal sidecar) — and compacts it on the way out.
    final snapshot = File(p.join(tmp.path, 'easytrack-user-snapshot.sqlite'));
    if (snapshot.existsSync()) await snapshot.delete();
    final escaped = snapshot.path.replaceAll("'", "''");
    await db.customStatement("VACUUM INTO '$escaped'");

    try {
      final manifest = <String, Object?>{
        'format': _formatId,
        'formatVersion': _formatVersion,
        'app': appVersion,
        'schemaVersion': schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'entryCount': await _diaryEntryCount(),
      };

      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final zip = File(p.join(tmp.path, 'easytrack-backup-$stamp.zip'));
      if (zip.existsSync()) await zip.delete();

      final encoder = ZipFileEncoder();
      encoder.create(zip.path);
      await encoder.addFile(snapshot, _dbEntryName);
      encoder.addArchiveFile(
        ArchiveFile.string(
          _manifestName,
          const JsonEncoder.withIndent('  ').convert(manifest),
        ),
      );
      await encoder.close();
      return zip;
    } finally {
      if (snapshot.existsSync()) await snapshot.delete();
    }
  }

  Future<int> _diaryEntryCount() async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM diary_entries WHERE deleted_at IS NULL',
        )
        .getSingle();
    return row.read<int>('n');
  }

  // --- Import (stage) ----------------------------------------------------

  /// Verifies [zip] and writes its database beside the live one as
  /// [stagedFileName], ready for [applyPendingImport]. Does not touch the live
  /// database. Throws [BackupException] on any problem, leaving nothing staged.
  Future<BackupInfo> stageImport(File zip) async {
    final docs = await documentsDirectory();
    final staged = File(p.join(docs.path, stagedFileName));
    if (staged.existsSync()) await staged.delete();

    try {
      final manifest = _extractInto(zip, staged);
      _validateManifest(manifest);
      _assertReadableUserDb(staged.path);
      return BackupInfo(
        appVersion: manifest['app'] as String?,
        createdAt: DateTime.tryParse(manifest['createdAt'] as String? ?? ''),
        entryCount: (manifest['entryCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      // A partly written or rejected stage must not linger and get applied on
      // the next boot.
      if (staged.existsSync()) await staged.delete();
      rethrow;
    }
  }

  /// Deletes any staged import, e.g. when the user backs out of the confirm.
  Future<void> discardStaged() async {
    final docs = await documentsDirectory();
    final staged = File(p.join(docs.path, stagedFileName));
    if (staged.existsSync()) await staged.delete();
  }

  /// Streams the `.sqlite` entry out of [zip] to [out] and returns the parsed
  /// manifest. Both come from one read of the archive's central directory; the
  /// database is decompressed straight to disk rather than into memory.
  Map<String, Object?> _extractInto(File zip, File out) {
    final input = InputFileStream(zip.path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } catch (e) {
        throw const BackupException('Die Datei ist kein lesbares Zip-Archiv.');
      }

      final manifestEntry = archive.files.firstWhere(
        (f) => f.isFile && p.basename(f.name) == _manifestName,
        orElse: () => throw const BackupException(
          'Keine gültige EasyTrack-Sicherung (Manifest fehlt).',
        ),
      );
      final Map<String, Object?> manifest;
      try {
        manifest =
            jsonDecode(utf8.decode(manifestEntry.readBytes()!))
                as Map<String, Object?>;
      } catch (e) {
        throw const BackupException('Das Sicherungs-Manifest ist beschädigt.');
      }

      final dbEntry = archive.files.firstWhere(
        (f) => f.isFile && f.name.toLowerCase().endsWith('.sqlite'),
        orElse: () => throw const BackupException(
          'Keine gültige EasyTrack-Sicherung (Datenbank fehlt).',
        ),
      );
      final output = OutputFileStream(out.path);
      try {
        dbEntry.writeContent(output);
      } finally {
        output.closeSync();
      }
      return manifest;
    } finally {
      input.closeSync();
    }
  }

  void _validateManifest(Map<String, Object?> manifest) {
    if (manifest['format'] != _formatId) {
      throw const BackupException('Diese Datei ist keine EasyTrack-Sicherung.');
    }
    final backupSchema = (manifest['schemaVersion'] as num?)?.toInt();
    if (backupSchema != null && backupSchema > schemaVersion) {
      throw BackupException(
        'Die Sicherung stammt aus einer neueren App-Version '
        '(Datenformat $backupSchema). Bitte zuerst EasyTrack aktualisieren.',
      );
    }
  }

  /// Opens the staged file read-only and confirms it is a sound EasyTrack user
  /// database: integrity holds, its `user_version` is not newer than this build
  /// reads, and the tables the app depends on are present (so a well-formed but
  /// unrelated SQLite file cannot pass as a backup).
  void _assertReadableUserDb(String path) {
    final sdb = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final integrity = sdb.select('PRAGMA integrity_check');
      if (integrity.first.values.first != 'ok') {
        throw const BackupException('Die Sicherung ist beschädigt.');
      }
      final version = sdb.select('PRAGMA user_version').first.values.first;
      if (version is int && version > schemaVersion) {
        throw BackupException(
          'Die Sicherung stammt aus einer neueren App-Version '
          '(Datenformat $version). Bitte zuerst EasyTrack aktualisieren.',
        );
      }
      // Throws if a table is missing — a random SQLite file must not restore.
      sdb.select('SELECT COUNT(*) FROM diary_entries');
      sdb.select('SELECT COUNT(*) FROM user_profile');
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException(
        'Die Sicherung ist keine gültige EasyTrack-Datenbank.',
      );
    } finally {
      sdb.close();
    }
  }

  // --- Import (apply, at boot) -------------------------------------------

  /// Swaps a previously [stageImport]ed database into place. Safe — and meant —
  /// to run before any database connection is opened (in `main()` and again
  /// during the in-app restart). A no-op, returning false, when nothing is
  /// staged.
  ///
  /// The old database and its WAL sidecars are removed, then the staged file is
  /// moved onto `user.sqlite`. Deleting the sidecars matters: a stale `-wal`
  /// left next to a swapped-in database would replay old pages over the restored
  /// data. The move retries briefly to ride out the moment a just-closed
  /// connection still holds the file (the transient lock the dev notes flag on
  /// Windows).
  static Future<bool> applyPendingImport({
    required Future<Directory> Function() documentsDirectory,
  }) async {
    final docs = await documentsDirectory();
    final staged = File(p.join(docs.path, stagedFileName));
    if (!staged.existsSync()) return false;
    final targetPath = p.join(docs.path, dbFileName);

    await _withRetry(() async {
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final f = File('$targetPath$suffix');
        if (f.existsSync()) await f.delete();
      }
      await staged.rename(targetPath);
    });
    return true;
  }

  static Future<void> _withRetry(
    Future<void> Function() action, {
    int attempts = 25,
  }) async {
    for (var i = 0; ; i++) {
      try {
        await action();
        return;
      } on FileSystemException {
        if (i >= attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}
