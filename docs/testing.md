# Testing notes

## Running

```bash
flutter test                 # Dart: 227 tests
cd tools/etl && npm test     # Node: 26 tests (the ETLs and the normalizer)
```

The ETL tests must run from `tools/etl`; Node's test runner resolves its file
patterns relative to the working directory.

## What is covered where

| Area | Where | Notes |
|---|---|---|
| Day arithmetic | `test/core/day_key_test.dart` | Month/year/leap boundaries, DST |
| Nutrient math | `test/core/nutrients_test.dart` | Scaling, unknown-vs-zero |
| German normalizer | `test/core/german_normalizer_test.dart` + `tools/etl/normalize.test.mjs` | Both sides, one shared fixture |
| Schema & sync metadata | `test/data/user_database_test.dart` | Triggers, tombstones, cascades |
| BLS pack integrity | `test/data/reference_database_test.dart` | Runs against the real 7,140-row pack |
| Food search | `test/data/bls_provider_test.dart` | Includes FTS-operator injection |
| OFF product search | `test/data/off_local_provider_test.dart` | Synthetic pack fixture, brand + barcode |
| OFF pack build | `tools/etl/build_off.test.mjs` | Sanity filter + FTS + ODbL meta |
| Pack manifest/installer | `test/data/pack_{manifest,installer,service}_test.dart` | SHA-256, integrity, failure-safe swap |
| OFF API + barcode chain | `test/data/{off_api_client,off_cache_repository,barcode_resolver}_test.dart` | Parse, cache, source-order, offline-after-hit |
| Ranking & merging | `test/data/search_orchestrator_test.dart` | Uses provider stubs |
| Diary logic | `test/data/diary_repository_test.dart` | Logging, editing, budget, water |
| Search UI | `test/features/food_search_screen_test.dart` | Real widget, real pack |
| Diary/settings/profile UI | `test/features/diary_screen_test.dart` | Phone-sized, catches layout overflow |

## Widget tests over drift streams

This was previously recorded as an unfixable gap. It is not — `test/features/
diary_screen_test.dart` now renders the diary, meal detail, settings and profile
screens against a real in-memory database. Three rules make it work, and breaking
any one of them produces a hang rather than a failure, which is why the gap looked
permanent:

1. **Never `pumpAndSettle`.** The loading state is a `CircularProgressIndicator`,
   whose animation never settles, so the call spins until its ten-minute timeout.
   Pump a bounded number of fixed-duration frames instead.
2. **Unmount the tree before the test body returns** — `pumpWidget(SizedBox())`
   followed by `pump(Duration(milliseconds: 1))`. Drift schedules a zero-duration
   timer when a query stream is cancelled, and the timer is created *during* that
   unmount frame. The trailing pump must carry a real duration: a bare `pump()`
   does not advance the fake clock, so a zero-duration timer never runs and the
   "timer still pending" assertion fires anyway.
3. **Never close the database from a widget test.** `close()` inside the
   fake-async zone never completes, and the whole `flutter test` process hangs
   without reporting. The in-memory database dies with the process; leaving it
   open only costs a "database opened twice" warning from drift.

The payoff is real: the first run of these tests found a 15px `RenderFlex`
overflow on the settings screen that the repository-level suite could never see.

Sizing matters too. The default 800x600 test surface is wider than any phone, so
overflows that would show on the device do not reproduce. `diary_screen_test.dart`
sets a 1080x2340 physical size at devicePixelRatio 3.

Still not covered: the navigation shell, the search screen's selection tray, and
the add-activity keypad. Running the app remains the check for those.

## Verifying by running

```bash
flutter run -d windows          # fastest iteration
flutter run -d <android-device> # required for camera, storage, pack download
```
