import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:easytrack/data/pack/off_pack_database.dart';
import 'package:easytrack/data/pack/pack_installer.dart';
import 'package:easytrack/data/pack/pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/off_pack_fixture.dart';

void main() {
  late Directory dir;
  late Uint8List packBytes;
  late String packSha;
  late File dest;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('off-inst-');
    final src = '${dir.path}/src.sqlite';
    writeOffPack(src);
    packBytes = File(src).readAsBytesSync();
    packSha = sha256.convert(packBytes).toString();
    dest = File('${dir.path}/off.sqlite');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  PackRelease release({int? bytes, String? sha, int minAppSchema = 1}) =>
      PackRelease(
        version: '2026-07-20',
        url: 'pack://test',
        bytes: bytes ?? packBytes.length,
        sha256: sha ?? packSha,
        rowCount: 2,
        minAppSchema: minAppSchema,
      );

  test('installs a verified pack and it opens', () async {
    final installer = PackInstaller((_) async => packBytes);
    await installer.install(release(), destination: dest);

    expect(dest.existsSync(), isTrue);
    final pack = OffPackDatabase.openAt(dest.path);
    expect(pack.foodCount, 2);
    expect(pack.region, 'dach');
    pack.dispose();
  });

  test('a checksum mismatch is refused and leaves the old pack live', () async {
    // An existing installation stands in for "the pack already on disk".
    dest.writeAsBytesSync(const [10, 20, 30]);

    var downloaded = false;
    final installer = PackInstaller((_) async {
      downloaded = true;
      return packBytes;
    });

    await expectLater(
      installer.install(release(sha: 'deadbeef'), destination: dest),
      throwsA(isA<PackInstallException>()),
    );
    expect(downloaded, isTrue);
    // Untouched.
    expect(dest.readAsBytesSync(), const [10, 20, 30]);
    // No leftover temp file.
    expect(File('${dest.path}.download').existsSync(), isFalse);
  });

  test('a size mismatch is refused', () async {
    dest.writeAsBytesSync(const [1, 2, 3]);
    final installer = PackInstaller((_) async => packBytes);

    await expectLater(
      installer.install(
        release(bytes: packBytes.length + 1),
        destination: dest,
      ),
      throwsA(isA<PackInstallException>()),
    );
    expect(dest.readAsBytesSync(), const [1, 2, 3]);
  });

  test('bytes that verify but are not a pack are refused', () async {
    // Well-formed checksum, garbage content: passes size + SHA, fails the
    // integrity/schema check when opened.
    final junk = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final junkSha = sha256.convert(junk).toString();
    dest.writeAsBytesSync(const [9, 9, 9]);

    final installer = PackInstaller((_) async => junk);
    await expectLater(
      installer.install(
        release(bytes: junk.length, sha: junkSha),
        destination: dest,
      ),
      throwsA(isA<PackInstallException>()),
    );
    expect(dest.readAsBytesSync(), const [9, 9, 9]);
  });

  test('installs a local pack file and returns its meta', () async {
    final src = File('${dir.path}/local.sqlite');
    writeOffPack(src.path);
    final installer = PackInstaller((_) async => packBytes);

    final meta = await installer.installLocalFile(src, destination: dest);

    expect(dest.existsSync(), isTrue);
    expect(meta['off_region'], 'dach');
    expect(meta['off_row_count'], '2');
    // The source is renamed into place, so it is consumed on success.
    expect(src.existsSync(), isFalse);

    final pack = OffPackDatabase.openAt(dest.path);
    expect(pack.foodCount, 2);
    pack.dispose();
  });

  test('installLocalFile refuses a file that is not a pack', () async {
    final junk = File('${dir.path}/junk.sqlite')
      ..writeAsBytesSync(List<int>.generate(64, (i) => i));
    dest.writeAsBytesSync(const [7, 7, 7]);
    final installer = PackInstaller((_) async => packBytes);

    await expectLater(
      installer.installLocalFile(junk, destination: dest),
      throwsA(isA<PackInstallException>()),
    );
    // The live pack is untouched.
    expect(dest.readAsBytesSync(), const [7, 7, 7]);
  });

  test('a pack needing a newer app is refused before downloading', () async {
    var downloaded = false;
    final installer = PackInstaller((_) async {
      downloaded = true;
      return packBytes;
    });

    await expectLater(
      installer.install(release(minAppSchema: 99), destination: dest),
      throwsA(isA<PackInstallException>()),
    );
    expect(downloaded, isFalse);
  });
}
