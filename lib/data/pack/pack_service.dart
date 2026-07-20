import 'dart:io';

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
        'https://REPLACE_ME.example/easytrack-packs/off-latest/manifest.json',
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
  /// records what was installed. Throws [PackInstallException] on any failure,
  /// leaving an already-installed pack untouched (the installer's guarantee).
  Future<PackRelease> install() async {
    final manifest = await fetchManifest();
    final region = selectedRegion;
    final release = manifest.releaseFor(region);
    if (release == null) {
      throw PackInstallException(
        'Für die Region ${region.label} ist kein Paket verfügbar.',
      );
    }

    await installer.install(release, destination: await packFile());

    await prefs.setString(_kInstalledVersion, release.version);
    await prefs.setString(_kInstalledRegion, region.wire);
    return release;
  }

  /// Removes the installed pack and forgets it. Search falls back to BLS-only.
  Future<void> deletePack() async {
    final file = await packFile();
    if (file.existsSync()) await file.delete();
    await prefs.remove(_kInstalledVersion);
    await prefs.remove(_kInstalledRegion);
  }
}
