import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'off_region.dart';
import 'pack_installer.dart';
import 'pack_manifest.dart';

/// A snapshot of where the product pack stands, for the Settings row.
class PackInstallState {
  const PackInstallState({
    required this.selectedRegion,
    required this.installedRegion,
    required this.installedVersion,
    required this.isInstalled,
  });

  final OffRegion selectedRegion;
  final OffRegion? installedRegion;
  final String? installedVersion;
  final bool isInstalled;

  /// The installed pack is for a different region than the one now selected, so
  /// the current pack no longer matches the user's choice.
  bool get regionChanged =>
      isInstalled &&
      installedRegion != null &&
      installedRegion != selectedRegion;
}

/// The outcome of a local (zip) install, drawn from the pack's own `pack_meta`.
class LocalPackInstall {
  const LocalPackInstall({
    required this.rowCount,
    required this.version,
    required this.region,
  });

  final int rowCount;
  final String version;

  /// The region the pack declares, or null when it does not name one.
  final OffRegion? region;
}

/// Owns the downloaded product pack: which region is selected, what is installed,
/// and the fetch-manifest → install flow.
///
/// Pack bookkeeping lives in [SharedPreferences], not the sync-ready user
/// database: the installed version and selected region are device-local, derive
/// from a re-downloadable file, and have no business being synced or backed up.
class PackService {
  PackService({
    required this.prefs,
    required this.installer,
    required this.fetchManifestText,
    required this.supportDirectory,
    this.manifestUrl = defaultManifestUrl,
  });

  /// The installed pack's filename in the app-support directory.
  static const packFileName = 'off.sqlite';

  static const _kSelectedRegion = 'off.region';
  static const _kInstalledVersion = 'off.installed_version';
  static const _kInstalledRegion = 'off.installed_region';

  /// Where the release manifest lives. A GitHub Release in production; override
  /// for local testing with
  ///   --dart-define=OFF_MANIFEST_URL=http://localhost:8000/manifest.json
  static const defaultManifestUrl = String.fromEnvironment(
    'OFF_MANIFEST_URL',
    defaultValue:
        'https://github.com/windowsaft/easytrack/releases/download/off-latest/manifest.json',
  );

  final SharedPreferences prefs;
  final PackInstaller installer;
  final Future<String> Function(Uri url) fetchManifestText;
  final Future<Directory> Function() supportDirectory;
  final String manifestUrl;

  OffRegion get selectedRegion =>
      OffRegion.fromWire(prefs.getString(_kSelectedRegion));

  Future<void> setRegion(OffRegion region) =>
      prefs.setString(_kSelectedRegion, region.wire);

  String? get installedVersion => prefs.getString(_kInstalledVersion);

  OffRegion? get installedRegion {
    final wire = prefs.getString(_kInstalledRegion);
    return wire == null ? null : OffRegion.fromWire(wire);
  }

  Future<File> packFile() async =>
      File(p.join((await supportDirectory()).path, packFileName));

  Future<bool> isInstalled() async => (await packFile()).existsSync();

  Future<PackInstallState> state() async => PackInstallState(
    selectedRegion: selectedRegion,
    installedRegion: installedRegion,
    installedVersion: installedVersion,
    isInstalled: await isInstalled(),
  );

  Future<PackManifest> fetchManifest() async =>
      PackManifest.parse(await fetchManifestText(Uri.parse(manifestUrl)));

  /// Downloads and installs the pack for the currently selected region, then
  /// records what was installed. [onProgress] reports download bytes and
  /// [cancel] aborts it. Throws [PackInstallException] on any failure (or
  /// [PackCancelledException] when cancelled), leaving an already-installed pack
  /// untouched (the installer's guarantee).
  Future<PackRelease> install({
    PackProgress? onProgress,
    PackCancelToken? cancel,
  }) async {
    final manifest = await fetchManifest();
    final region = selectedRegion;
    final release = manifest.releaseFor(region);
    if (release == null) {
      throw PackInstallException(
        'Für die Region ${region.wire} ist kein Paket verfügbar.',
      );
    }

    await installer.install(
      release,
      destination: await packFile(),
      onProgress: onProgress,
      cancel: cancel,
    );

    await prefs.setString(_kInstalledVersion, release.version);
    await prefs.setString(_kInstalledRegion, region.wire);
    return release;
  }

  /// Installs a pack from a user-supplied **zip** that contains the pack's
  /// `.sqlite`. This is the offline path for when the packs are not hosted on a
  /// GitHub Release: build the pack locally, zip it, copy it onto the phone, and
  /// import it here.
  ///
  /// No manifest and no checksum — the pack vouches for itself the same way a
  /// downloaded one does (integrity_check + schema + `off_foods`). The `.sqlite`
  /// is streamed out of the zip to a temp file so an ~85 MB pack is never held
  /// in memory at once. The installed version/region are read from the pack's
  /// own `pack_meta`. A failure leaves any already-installed pack untouched.
  Future<LocalPackInstall> installFromZip(File zip) async {
    final destination = await packFile();
    final tmp = File('${destination.path}.import');
    if (tmp.existsSync()) await tmp.delete();
    try {
      _extractPackSqlite(zip, tmp);
      final meta = await installer.installLocalFile(
        tmp,
        destination: destination,
      );

      final version = (meta['off_version']?.trim().isNotEmpty ?? false)
          ? meta['off_version']!.trim()
          : 'Lokal importiert';
      final regionWire = meta['off_region'];
      final region = regionWire == null ? null : OffRegion.fromWire(regionWire);
      final rowCount = int.tryParse(meta['off_row_count'] ?? '') ?? 0;

      await prefs.setString(_kInstalledVersion, version);
      if (region != null) {
        await prefs.setString(_kInstalledRegion, region.wire);
      }
      return LocalPackInstall(
        rowCount: rowCount,
        version: version,
        region: region,
      );
    } finally {
      // installLocalFile renames tmp into place on success, so this only fires
      // when extraction or verification failed partway.
      if (tmp.existsSync()) await tmp.delete();
    }
  }

  /// Streams the single `.sqlite` entry out of [zip] to [out]. Reads the zip's
  /// central directory, then decompresses only the pack entry to disk.
  void _extractPackSqlite(File zip, File out) {
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entry = archive.files.firstWhere(
        (f) => f.isFile && f.name.toLowerCase().endsWith('.sqlite'),
        orElse: () => throw const PackInstallException(
          'Im Zip wurde keine .sqlite-Datei gefunden.',
        ),
      );
      final output = OutputFileStream(out.path);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    } finally {
      input.closeSync();
    }
  }

  /// Removes the installed pack and forgets it. Search falls back to BLS-only.
  Future<void> deletePack() async {
    final file = await packFile();
    if (file.existsSync()) await file.delete();
    await prefs.remove(_kInstalledVersion);
    await prefs.remove(_kInstalledRegion);
  }
}
