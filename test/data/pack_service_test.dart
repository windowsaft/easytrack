import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:easytrack/data/pack/off_pack_database.dart';
import 'package:easytrack/data/pack/off_region.dart';
import 'package:easytrack/data/pack/pack_installer.dart';
import 'package:easytrack/data/pack/pack_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/off_pack_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Uint8List bytes;
  late String sha;
  late SharedPreferences prefs;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('off-svc-');
    final src = '${dir.path}/src.sqlite';
    writeOffPack(src);
    bytes = File(src).readAsBytesSync();
    sha = sha256.convert(bytes).toString();

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String manifestJson() =>
      '{"schemaVersion":1,"packs":{"dach":{"version":"2026-07-20",'
      '"url":"pack://dach","bytes":${bytes.length},"sha256":"$sha",'
      '"rowCount":2,"minAppSchema":1}}}';

  PackService build() => PackService(
    prefs: prefs,
    installer: PackInstaller((_, {expectedBytes, onProgress, cancel}) async => bytes),
    fetchManifestText: (_, {expectedBytes, onProgress, cancel}) async => manifestJson(),
    supportDirectory: () async => dir,
    manifestUrl: 'http://test/manifest.json',
  );

  test('defaults to the DACH region', () {
    expect(build().selectedRegion, OffRegion.dach);
  });

  test('install downloads the pack and records what landed', () async {
    final service = build();
    expect(await service.isInstalled(), isFalse);

    final release = await service.install();
    expect(release.rowCount, 2);
    expect(await service.isInstalled(), isTrue);
    expect(service.installedVersion, '2026-07-20');
    expect(service.installedRegion, OffRegion.dach);

    // The installed file is a real, openable pack.
    final pack = OffPackDatabase.openAt((await service.packFile()).path);
    expect(pack.foodCount, 2);
    pack.dispose();
  });

  test('changing region marks the installed pack as out of date', () async {
    final service = build();
    await service.install();
    await service.setRegion(OffRegion.world);

    final state = await service.state();
    expect(state.selectedRegion, OffRegion.world);
    expect(state.installedRegion, OffRegion.dach);
    expect(state.regionChanged, isTrue);
  });

  test(
    'install throws when the selected region has no published pack',
    () async {
      final service = build();
      await service.setRegion(OffRegion.world); // manifest only carries dach
      await expectLater(
        service.install(),
        throwsA(isA<PackInstallException>()),
      );
      expect(await service.isInstalled(), isFalse);
    },
  );

  test('installFromZip extracts the .sqlite and installs it', () async {
    // A pack built elsewhere, zipped, and copied onto the device.
    final packPath = '${dir.path}/src-pack.sqlite';
    writeOffPack(packPath);
    final zipPath = '${dir.path}/pack.zip';
    final encoder = ZipFileEncoder()..create(zipPath);
    encoder.addFileSync(File(packPath), 'off.sqlite');
    encoder.closeSync();

    final service = build();
    expect(await service.isInstalled(), isFalse);

    final result = await service.installFromZip(File(zipPath));
    expect(result.rowCount, 2);
    expect(result.version, '2026-07-20');
    expect(result.region, OffRegion.dach);

    // Recorded as installed, from the pack's own meta — no manifest involved.
    expect(await service.isInstalled(), isTrue);
    expect(service.installedVersion, '2026-07-20');
    expect(service.installedRegion, OffRegion.dach);

    final pack = OffPackDatabase.openAt((await service.packFile()).path);
    expect(pack.foodCount, 2);
    pack.dispose();
  });

  test('installFromZip rejects a zip that has no .sqlite', () async {
    final note = File('${dir.path}/note.txt')..writeAsStringSync('kein pack');
    final zipPath = '${dir.path}/empty.zip';
    final encoder = ZipFileEncoder()..create(zipPath);
    encoder.addFileSync(note, 'note.txt');
    encoder.closeSync();

    final service = build();
    await expectLater(
      service.installFromZip(File(zipPath)),
      throwsA(isA<PackInstallException>()),
    );
    expect(await service.isInstalled(), isFalse);
  });

  test('deletePack removes the file and forgets the version', () async {
    final service = build();
    await service.install();

    await service.deletePack();
    expect(await service.isInstalled(), isFalse);
    expect(service.installedVersion, isNull);
    expect(service.installedRegion, isNull);
  });
}
