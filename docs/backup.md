# Data backup (export / import)

Local-first with no account means the only copy of a user's data is the SQLite
file on their phone. Backup gives them a portable copy they own: export the
whole database as a zip, import it back on a reinstall or a new device.

Reached from **Einstellungen → DATENSICHERUNG** (both directions) and from the
**onboarding welcome step** (restore only — there is nothing to export on a
fresh install).

## What a backup is

A zip containing exactly two entries:

| Entry | What it is |
|---|---|
| `user.sqlite` | The whole user database, as a `VACUUM INTO` snapshot |
| `backup.json` | A manifest describing the build and schema it came from |

```json
{
  "format": "easytrack-backup",
  "formatVersion": 1,
  "app": "1.0.0+1",
  "schemaVersion": 4,
  "createdAt": "2026-07-23T22:44:40.033Z",
  "entryCount": 14
}
```

Bundling the raw database — rather than serialising each table to JSON — keeps
every row, its sync bookkeeping (the `SyncableTable` columns) and its
soft-delete tombstones intact, and automatically covers any table a future
schema adds. `VACUUM INTO` is used instead of a plain file copy because the live
database runs in WAL mode: a copy could miss committed frames still sitting in
the `-wal` sidecar. `VACUUM INTO` writes a single, fully checkpointed, compacted
file.

The whole design mirrors the OFF product-pack installer (`data/pack/`): pick with
`file_selector`, stream out of the zip with `package:archive`, verify, then swap
— a failure never touches the live data.

## Export

`BackupService.exportToZip` builds the zip in the temp directory; the UI hands it
to the system share sheet (`share_plus`). Because it is shared as a real
`application/zip` file, the Android share sheet lists the Files app ("In Datei
speichern") alongside the usual targets — that is the save-to-a-folder path.
Share-sheet-only was a deliberate choice: `file_selector` on Android cannot write
to a picked folder (a SAF `content://` tree URI is not a `dart:io` path), so a
separate "choose folder" button would either not work or just re-open the share
sheet.

## Import — the two-step boot swap

You cannot overwrite `user.sqlite` while a drift connection holds it, so import
is split across a restart:

1. **`stageImport(zip)`** — verifies and stages, without touching the live
   database. Checks: the manifest's `format` is ours and its `schemaVersion` is
   not newer than this build; the database passes `integrity_check`; its
   `user_version` is not newer than this build reads; and the tables the app
   depends on (`diary_entries`, `user_profile`) are present, so an unrelated but
   well-formed SQLite file cannot restore. On success the database is written
   beside the live one as `user.sqlite.import`. Any failure throws
   `BackupException` and leaves nothing staged.
2. **`applyPendingImport()`** — runs with *no* database open. Deletes
   `user.sqlite` and its `-wal`/`-shm`/`-journal` sidecars (a stale `-wal` left
   next to a swapped-in database would replay old pages over the restore), then
   renames the staged file into place. It retries the move briefly to ride out
   the moment a just-closed connection still holds the file.

`AppBoot` (`lib/app_boot.dart`) hosts the `ProviderScope` and bridges the two.
`restartForImport` drops the scope (disposing the `UserDatabase` provider, which
closes the connection), awaits a frame, runs `applyPendingImport`, then mounts a
fresh scope that opens the restored database. `main()` also calls
`applyPendingImport` before `runApp`, so an app kill between staging and the
restart still lands the import on the next cold start.

## Files

| File | Role |
|---|---|
| `lib/data/backup/backup_service.dart` | Export, stage, verify, apply |
| `lib/features/backup/backup_flow.dart` | Shared export/import UI flows |
| `lib/app_boot.dart` | The restart that applies a staged import |
| `lib/core/di/providers.dart` | `backupServiceProvider` |

## A note on diary resilience

Building the sample data surfaced a latent bug: `DiaryRepository.watchDay`
combines several DB streams, and its combiner calls `MealType.fromWire`. A diary
row with an unrecognised meal string (which a hand-edited or foreign import can
carry) made the combiner throw *inside* a stream's `onData`, where the exception
escaped as an uncaught zone error and the stream simply never emitted — an
infinite loading spinner. `Rx.combineLatest` now guards the combiner and routes
a throw to the stream's error channel, so bad data shows the visible "Fehler beim
Laden" screen instead of hanging. Regression test: `test/data/diary_repository_test.dart`
→ "resilience".

## Sample backup tool

`tool/make_sample_backup.dart` generates a realistic backup zip for testing the
import flow, so you do not have to hand-enter data on the device.

```bash
"C:/dev/flutter/bin/flutter.bat" test tool/make_sample_backup.dart
```

It runs via `flutter test` (not `dart run`) so the native `sqlite3` resolves the
same way the test suite's does. It seeds a fresh in-memory database — profile +
target, a week of diary/water/activity/weight data **dated relative to today**, a
custom food and a favourite recipe (Chili con Carne, 5 ingredients, cooked-weight
yield + portion size) — asserts the data is actually queryable, runs the real
`BackupService.exportToZip`, and writes the result to:

```
build/easytrack-sample-backup.zip
```

`build/` is gitignored, and the tool lives outside `test/`, so neither affects
the normal `flutter test` run or the repository. Push it to the phone and import
it via Einstellungen → DATENSICHERUNG or the onboarding restore card:

```bash
adb push build/easytrack-sample-backup.zip /sdcard/Download/
```

The dates are computed from `DateTime.now()` at generation time, so if the
device's clock is *behind* the machine that generated the zip, some entries land
on a day the device considers the future — reachable with the diary's next-day
chevron. Regenerate any time the seed or the schema changes; the assertion in the
tool fails loudly if a section (e.g. the recipe) would ship empty.
