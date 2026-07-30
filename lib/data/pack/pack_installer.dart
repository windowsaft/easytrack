import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'off_pack_database.dart';
import 'pack_manifest.dart';

/// Reports download progress: [received] bytes so far out of [total].
typedef PackProgress = void Function(int received, int total);

/// Cooperative cancellation for an in-flight download. The UI holds one and
/// calls [cancel]; the downloader checks [isCancelled] between chunks.
class PackCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Thrown when a download is cancelled via a [PackCancelToken]. Kept distinct
/// from [PackInstallException] so the UI can treat it as "aborted", not "failed".
class PackCancelledException implements Exception {
  const PackCancelledException();
  @override
  String toString() => 'PackCancelledException';
}

/// Fetches the bytes at [url]. Injected so the installer can be tested without a
/// network, and so the production `http` client stays out of the pure logic.
/// [expectedBytes] seeds the progress total when the response omits a length;
/// [onProgress] fires as bytes arrive; [cancel] aborts between chunks.
typedef PackDownloader =
    Future<Uint8List> Function(
      Uri url, {
      int? expectedBytes,
      PackProgress? onProgress,
      PackCancelToken? cancel,
    });

/// Thrown when a downloaded pack does not match what the manifest promised, or
/// cannot be read as a valid pack. The installer guarantees an existing pack is
/// never touched when this is thrown.
class PackInstallException implements Exception {
  const PackInstallException(this.message);
  final String message;
  @override
  String toString() => 'PackInstallException: $message';
}

/// Installs a product pack: download → verify → atomic swap.
///
/// The invariant the whole design turns on: **a failure leaves the currently
/// installed pack live.** Nothing touches the destination file until the
/// downloaded bytes have matched the manifest's size and SHA-256 *and* opened as
/// a schema-compatible SQLite database that passes `integrity_check`. Only then
/// is the temp file renamed over the destination.
class PackInstaller {
  const PackInstaller(this.download);

  final PackDownloader download;

  Future<void> install(
    PackRelease release, {
    required File destination,
    PackProgress? onProgress,
    PackCancelToken? cancel,
  }) async {
    // An app too old for this pack refuses it up front rather than downloading
    // megabytes it cannot read.
    if (release.minAppSchema > OffPackDatabase.supportedSchemaVersion) {
      throw PackInstallException(
        'pack needs app schema ${release.minAppSchema}, this build supports '
        '${OffPackDatabase.supportedSchemaVersion}',
      );
    }

    final bytes = await download(
      Uri.parse(release.url),
      expectedBytes: release.bytes,
      onProgress: onProgress,
      cancel: cancel,
    );

    if (bytes.length != release.bytes) {
      throw PackInstallException(
        'size mismatch: got ${bytes.length} bytes, expected ${release.bytes}',
      );
    }

    final digest = sha256.convert(bytes).toString();
    if (digest != release.sha256) {
      throw PackInstallException(
        'checksum mismatch: got $digest, expected ${release.sha256}',
      );
    }

    await destination.parent.create(recursive: true);
    final tmp = File('${destination.path}.download');
    if (tmp.existsSync()) await tmp.delete();
    await tmp.writeAsBytes(bytes, flush: true);

    try {
      _assertReadablePack(tmp.path);
    } catch (e) {
      // The verified-but-unreadable file is discarded; the live pack is intact.
      if (tmp.existsSync()) await tmp.delete();
      throw PackInstallException('downloaded pack is not readable: $e');
    }

    await _swap(tmp, destination);
  }

  /// Installs a pack from a local file already on disk — one the user picked and
  /// we extracted from a zip — rather than a downloaded release.
  ///
  /// There is no manifest to match, so the pack must vouch for itself with
  /// exactly the checks a downloaded pack passes: `integrity_check` holds, the
  /// schema is one this build reads, and `off_foods` is present. On success
  /// [source] is renamed into place (consumed) and the pack's `pack_meta` is
  /// returned so the caller can record its version and region without a manifest.
  /// On any failure a `PackInstallException` is thrown and the currently
  /// installed pack is left untouched.
  Future<Map<String, String>> installLocalFile(
    File source, {
    required File destination,
  }) async {
    if (!source.existsSync()) {
      throw const PackInstallException(
        'Die ausgewählte Datei wurde nicht gefunden.',
      );
    }
    try {
      _assertReadablePack(source.path);
    } catch (e) {
      throw PackInstallException('Datei ist kein gültiges Produktpaket: $e');
    }
    final meta = _readMeta(source.path);
    await destination.parent.create(recursive: true);
    await _swap(source, destination);
    return meta;
  }

  Map<String, String> _readMeta(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final rows = db.select('SELECT key, value FROM pack_meta');
      return {
        for (final row in rows) row['key'] as String: row['value'] as String,
      };
    } finally {
      db.close();
    }
  }

  /// Opens the candidate read-only and confirms it is a sound, compatible pack:
  /// SQLite integrity holds, the schema is one this build reads, and the
  /// `off_foods` table is actually present.
  void _assertReadablePack(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final integrity = db.select('PRAGMA integrity_check');
      final result = integrity.first.values.first;
      if (result != 'ok') {
        throw StateError('integrity_check returned "$result"');
      }

      final meta = db.select(
        "SELECT value FROM pack_meta WHERE key = 'schema_version'",
      );
      final schema = meta.isEmpty
          ? 0
          : int.tryParse(meta.first['value'] as String) ?? 0;
      if (schema > OffPackDatabase.supportedSchemaVersion) {
        throw StateError('pack schema $schema is newer than this build reads');
      }

      // Throws if the table is missing — a well-formed SQLite file of the wrong
      // shape must not pass as a product pack.
      db.select('SELECT COUNT(*) FROM off_foods');
    } finally {
      db.close();
    }
  }

  Future<void> _swap(File tmp, File destination) async {
    if (!destination.existsSync()) {
      await tmp.rename(destination.path);
      return;
    }
    try {
      // POSIX rename replaces the destination atomically — the property that
      // makes an interrupted install safe on the phone.
      await tmp.rename(destination.path);
    } on FileSystemException {
      // Windows rename throws when the target exists. The candidate has already
      // passed every check, so deleting the old file here cannot lose good data;
      // only the desktop dev path takes this branch.
      await destination.delete();
      await tmp.rename(destination.path);
    }
  }
}
