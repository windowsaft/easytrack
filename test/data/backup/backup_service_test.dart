import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:easytrack/data/backup/backup_service.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late UserDatabase db;
  late Directory docs;
  late Directory tmp;

  setUp(() async {
    db = UserDatabase.forTesting();
    docs = await Directory.systemTemp.createTemp('et-backup-docs');
    tmp = await Directory.systemTemp.createTemp('et-backup-tmp');
  });

  tearDown(() async {
    await db.close();
    for (final dir in [docs, tmp]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  BackupService serviceWith({int schemaVersion = 4}) => BackupService(
    db: db,
    documentsDirectory: () async => docs,
    temporaryDirectory: () async => tmp,
    appVersion: '1.0.0+1',
    schemaVersion: schemaVersion,
  );

  Future<void> seedEntry({int day = 20260719}) async {
    await db
        .into(db.diaryEntries)
        .insert(
          DiaryEntriesCompanion.insert(
            loggedOn: day,
            meal: 'breakfast',
            sourceType: 'bls',
            sourceId: 'C133000',
            nameSnapshot: 'Hafer Flocken',
            amountG: 50,
            kcal: 174,
            proteinG: 6.61,
            carbsG: 29.35,
            fatG: 3.5,
          ),
        );
  }

  File stagedFile() => File(p.join(docs.path, BackupService.stagedFileName));
  File liveDbFile() => File(p.join(docs.path, BackupService.dbFileName));

  group('export', () {
    test('produces a zip carrying the database and a manifest', () async {
      await seedEntry();
      final zip = await serviceWith().exportToZip();

      expect(zip.existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(<String>['user.sqlite', 'backup.json']));
    });
  });

  group('export → stageImport round trip', () {
    test('stages the database and reports what it holds', () async {
      await seedEntry();
      await seedEntry(day: 20260720);
      final zip = await serviceWith().exportToZip();

      final info = await serviceWith().stageImport(zip);

      expect(info.entryCount, 2);
      expect(info.appVersion, '1.0.0+1');
      expect(info.createdAt, isNotNull);
      expect(stagedFile().existsSync(), isTrue);
    });

    test('applyPendingImport swaps the staged file into place', () async {
      await seedEntry();
      final zip = await serviceWith().exportToZip();
      await serviceWith().stageImport(zip);

      // No live database file yet in this fresh docs dir.
      expect(liveDbFile().existsSync(), isFalse);

      final applied = await BackupService.applyPendingImport(
        documentsDirectory: () async => docs,
      );

      expect(applied, isTrue);
      expect(liveDbFile().existsSync(), isTrue);
      expect(stagedFile().existsSync(), isFalse, reason: 'staged file consumed');
    });

    test('applyPendingImport is a no-op when nothing is staged', () async {
      final applied = await BackupService.applyPendingImport(
        documentsDirectory: () async => docs,
      );
      expect(applied, isFalse);
    });

    test('applyPendingImport clears stale WAL sidecars of the old db', () async {
      await seedEntry();
      final zip = await serviceWith().exportToZip();
      await serviceWith().stageImport(zip);

      // A leftover -wal beside the target must not survive the swap, or it would
      // replay old pages over the restored database.
      await liveDbFile().writeAsString('old');
      final wal = File('${liveDbFile().path}-wal');
      await wal.writeAsString('stale');

      await BackupService.applyPendingImport(documentsDirectory: () async => docs);

      expect(wal.existsSync(), isFalse);
    });
  });

  group('stageImport rejects bad input', () {
    test('a zip without a manifest', () async {
      final bad = File(p.join(tmp.path, 'bad.zip'));
      final encoder = ZipFileEncoder();
      encoder.create(bad.path);
      encoder.addArchiveFile(ArchiveFile.string('notes.txt', 'hello'));
      await encoder.close();

      await expectLater(
        serviceWith().stageImport(bad),
        throwsA(isA<BackupException>()),
      );
      expect(stagedFile().existsSync(), isFalse, reason: 'nothing left staged');
    });

    test('a backup from a newer schema than this build reads', () async {
      await seedEntry();
      // Written by a "future" build at schema 9.
      final zip = await serviceWith(schemaVersion: 9).exportToZip();

      // Read by this build, which only understands schema 4.
      await expectLater(
        serviceWith(schemaVersion: 4).stageImport(zip),
        throwsA(isA<BackupException>()),
      );
      expect(stagedFile().existsSync(), isFalse);
    });

    test('a zip whose database is not an EasyTrack database', () async {
      // Valid manifest, but the .sqlite is a sound but unrelated SQLite file
      // (no diary_entries / user_profile tables).
      final foreignFile = File(p.join(tmp.path, 'foreign.sqlite'));
      final raw = sqlite3.open(foreignFile.path);
      raw.execute('CREATE TABLE t (x INTEGER)');
      raw.close();

      final zip = File(p.join(tmp.path, 'foreign.zip'));
      final encoder = ZipFileEncoder();
      encoder.create(zip.path);
      await encoder.addFile(foreignFile, 'user.sqlite');
      encoder.addArchiveFile(
        ArchiveFile.string(
          'backup.json',
          '{"format":"easytrack-backup","schemaVersion":4}',
        ),
      );
      await encoder.close();

      await expectLater(
        serviceWith().stageImport(zip),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
