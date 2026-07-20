import 'dart:convert';

import 'off_region.dart';

/// One downloadable product pack, as described by the release manifest.
///
/// Every field the installer needs to fetch and trust a pack without opening it
/// first: where it is, how big it should be, its SHA-256, and the minimum app
/// schema that can read it.
class PackRelease {
  const PackRelease({
    required this.version,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.rowCount,
    required this.minAppSchema,
  });

  /// Opaque release id (a date, in the current pipeline). Compared as a string
  /// against the installed version to decide whether an update exists.
  final String version;
  final String url;
  final int bytes;
  final String sha256;
  final int rowCount;

  /// The oldest pack schema the app must support to read this pack. An app
  /// older than this refuses the pack rather than mis-reading its columns.
  final int minAppSchema;

  factory PackRelease.fromJson(Map<String, dynamic> json) => PackRelease(
    version: json['version'] as String,
    url: json['url'] as String,
    bytes: (json['bytes'] as num).toInt(),
    sha256: (json['sha256'] as String).toLowerCase(),
    rowCount: (json['rowCount'] as num).toInt(),
    minAppSchema: (json['minAppSchema'] as num?)?.toInt() ?? 1,
  );
}

/// The release manifest: a schema version plus one [PackRelease] per region.
///
/// Fetched from a stable URL (a GitHub Release in production). The Settings
/// region toggle just selects which entry to install.
class PackManifest {
  const PackManifest({required this.schemaVersion, required this.packs});

  final int schemaVersion;

  /// Keyed by [OffRegion.wire].
  final Map<String, PackRelease> packs;

  PackRelease? releaseFor(OffRegion region) => packs[region.wire];

  factory PackManifest.fromJson(Map<String, dynamic> json) {
    final packs = <String, PackRelease>{};
    final raw = json['packs'];
    if (raw is Map<String, dynamic>) {
      for (final entry in raw.entries) {
        packs[entry.key] = PackRelease.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return PackManifest(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      packs: packs,
    );
  }

  static PackManifest parse(String source) =>
      PackManifest.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
