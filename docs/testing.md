# Testing notes

## Running

```bash
flutter test                 # Dart: 118 tests
cd tools/etl && npm test     # Node: 15 tests (the ETL and its normalizer)
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
| Ranking & merging | `test/data/search_orchestrator_test.dart` | Uses provider stubs |
| Diary logic | `test/data/diary_repository_test.dart` | Logging, editing, budget, water |
| Search UI | `test/features/food_search_screen_test.dart` | Real widget, real pack |

## Known gap: widget tests over drift streams

There is **no widget test for the diary screen or the navigation shell**, and this
is a deliberate, unsatisfying compromise rather than an oversight.

Any widget test whose tree subscribes to a drift `.watch()` stream fails or hangs
under `flutter_test`'s fake-async clock. Drift schedules a zero-duration timer
when a query stream is cancelled; if that happens during the framework's teardown
the test fails with "Pending timers", and unmounting inside the test body to flush
it instead causes `pumpAndSettle` to spin. The search screen tests pass precisely
because that screen reads a one-shot `StreamProvider` rather than a live database
stream.

What covers the diary in the meantime:

- `test/data/diary_repository_test.dart` — 19 tests over the real logic: nutrient
  scaling, snapshot storage, per-day isolation, editing, soft delete, the water
  undo ordering, and the activity safety factor.
- Running the app (`flutter run -d windows`) and confirming the rendered day view.

Worth revisiting by wrapping the day summary in a plain `Stream` fed from a manual
controller in tests, or by checking whether a newer drift release changes the
cancellation behaviour. Until then, **changes to diary widgets must be verified by
running the app**, not by the test suite alone.

## Verifying by running

```bash
flutter run -d windows          # fastest iteration
flutter run -d <android-device> # required for camera, storage, pack download
```
