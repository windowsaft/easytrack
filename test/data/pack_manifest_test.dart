import 'package:easytrack/data/pack/off_region.dart';
import 'package:easytrack/data/pack/pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const json = '''
  {
    "schemaVersion": 1,
    "packs": {
      "dach": {
        "version": "2026-07-20",
        "url": "https://example.test/off_dach.sqlite",
        "bytes": 36864,
        "sha256": "BA12328C",
        "rowCount": 20,
        "minAppSchema": 1
      },
      "de": {
        "version": "2026-07-20",
        "url": "https://example.test/off_de.sqlite",
        "bytes": 12345,
        "sha256": "abcd",
        "rowCount": 10,
        "minAppSchema": 1
      }
    }
  }
  ''';

  test('parses a manifest and selects a release per region', () {
    final manifest = PackManifest.parse(json);
    expect(manifest.schemaVersion, 1);

    final dach = manifest.releaseFor(OffRegion.dach)!;
    expect(dach.version, '2026-07-20');
    expect(dach.bytes, 36864);
    expect(dach.rowCount, 20);
    // Checksums are lower-cased on parse so the comparison in the installer is
    // case-insensitive.
    expect(dach.sha256, 'ba12328c');

    expect(manifest.releaseFor(OffRegion.de)!.rowCount, 10);
  });

  test('a region with no published pack is null, not an error', () {
    final manifest = PackManifest.parse(json);
    expect(manifest.releaseFor(OffRegion.world), isNull);
  });

  test('minAppSchema defaults to 1 when absent', () {
    final manifest = PackManifest.parse('''
      {"schemaVersion": 1, "packs": {"dach": {
        "version": "v", "url": "u", "bytes": 1, "sha256": "x", "rowCount": 1
      }}}
    ''');
    expect(manifest.releaseFor(OffRegion.dach)!.minAppSchema, 1);
  });
}
