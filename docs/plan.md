# EasyTrack — personal calorie & hydration tracker

## Context

Lifesum and its peers are subscription-gated, cloud-only, and full of features you don't
want while missing ones you do. This builds a self-owned replacement: mobile-first,
local-first, no account, no subscription, with a food database that actually knows German
products.

Target directory `C:\dev\easytrack` is currently empty and not a git repo. Work is tracked
with conventional commits from the first commit onward.

**Design goal:** log a meal in under 10 seconds — scan a barcode or type three letters,
tap a portion, done.

---

## Decisions (confirmed)

| Area | Decision |
|---|---|
| Stack | Flutter 3.44.1 + Drift (SQLite) + Riverpod |
| Platforms | Android now (sideloaded APK); web/desktop later, same codebase |
| Storage | Local-first, sync-ready schema; no server built now |
| Food data | BLS 4.0 offline → OFF offline → OFF online fallback → USDA later |
| OFF scope | DACH default, switchable in Settings (DE-only / DACH / World) |
| Targets | Mifflin-St Jeor TDEE with manual override |
| Activity | Burned calories **increase** the day's budget, × safety factor (default 0.8) |
| Tracked | kcal + protein/carbs/fat, custom foods, recipes, favorites, weight |

Verified on this machine: Flutter 3.44.1 stable, Android SDK 36.1 (licenses accepted),
Windows + Edge devices, Node.js present, Java via Android Studio JBR.

**Why Drift:** Hive and Isar were abandoned by their author and MongoDB killed Realm's
sync. Isar's Rust core makes forking impractical. Drift is SQL-backed, type-safe, actively
maintained, reactive, and runs on web via WASM — the only choice that survives "web later"
without a rewrite.

---

## Data sources

**BLS 4.0** — Germany's national nutrient database (Max Rubner-Institut). Became free of
licence fees in v4.0 and is now open data under **CC BY 4.0**: 7,140 foods, 138 nutrients,
no registration. Best-in-class for German generic foods ("Vollkornbrot", "Quark 40%"), and
small enough to ship inside the app.

> **Verified during planning:** the download is `BLS_4_0_2025_DE.zip` containing an
> **XLSX workbook (~13.6 MB, 418 columns)** — 3 identity columns then 138 nutrients ×
> 3 columns each (value, data-origin code, reference). All values per 100 g edible portion.
> This corrects the initial assumption of a CSV.

**Open Food Facts** — branded/barcode products. Full dump is ~0.9 GB gzipped / ~9 GB
uncompressed, so a build-time ETL filters it to the selected region. Online API is the
fallback for anything missing, and every online hit is cached locally.

**USDA FoodData Central** — deferred, designed for. Free key, 1,000 req/hour.

**Attribution is mandatory** (BLS is CC BY 4.0, OFF is ODbL). Required citation:

> Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0 – Deutsche
> Nährstoffdatenbank. Karlsruhe. DOI: 10.25826/Data20251217-134202-0

Shown in Settings → Datenquellen, as a source chip on each food detail screen, and in
`showLicensePage`. Do not ship OFF images (CC-BY-SA).

---

## Architecture

```
lib/
  core/          result types, DI, formatting, date utils, german_normalizer.dart
  data/
    db/          user_database.dart, reference_database.dart
    food/        food_provider.dart + bls/off_local/off_online/custom/recipe impls
    pack/        manifest check, download, verify, atomic swap
    repositories/
  domain/        entities, TDEE + portion math, use cases
  features/      diary/ search/ recipes/ hydration/ activity/ profile/
tools/etl/       build_bls.mjs, build_off.sql, finalize.mjs, de_food_morphemes.txt
```

### Two physical databases, deliberately not ATTACHed

- **`user.sqlite`** — everything you create. WAL, backed up, never touched by data updates.
- **`reference.sqlite`** — BLS + OFF slice, read-only, replaced wholesale on update.

Separate Drift classes (`UserDatabase`, `ReferenceDatabase`), no `ATTACH`: attaching would
pin the reference file open, force both into one migration namespace, and break the web
target. The reference DB has no Drift migrations — a `pack_meta.schema_version` mismatch
triggers re-download instead.

**Every diary entry stores a denormalized nutrient snapshot.** This is what makes wholesale
replacement safe, and it is independently correct: if OFF corrects a product's calories in
September, your August logs must not silently change. Same for recipe ingredients.

### Sync readiness

No server now, but every user-owned table gets a `SyncableTable` mixin from migration v1:
`id` (UUIDv7 PK — time-ordered, so index locality and free chronological ordering),
`createdAt`, `updatedAt`, `deletedAt` (tombstone), `syncRev`, `dirty`. Rows are never
deleted, only tombstoned; all reads filter `deletedAt IS NULL` via a shared helper. A
`SyncCursor` table is created now though nothing writes it. A Drift update interceptor
forces `updatedAt = now, dirty = 1` so no code path can forget. Retrofitting this later
would mean a backfill across every table; adding it now is free.

---

## Key tables

**Reference:** `bls_foods` (bls_code, name_de/en, search_text, ~28 surfaced nutrients of
138 — the other 110 triple the table for near-zero value), `off_foods` (barcode PK, name,
brands, serving_size_g, 8 core nutrients, completeness_score), FTS tables, `pack_meta`.

**User:** `custom_foods`, `recipes` + `recipe_ingredients` (with snapshots),
`diary_entries`, `water_log`, `activity_entries`, `weight_log`, `user_profile`, `targets`,
`off_cache`, `pinned_foods`.

Three details that are painful to retrofit:

- `diary_entries.logged_on` stores the **local calendar day as `INTEGER yyyymmdd`**, not a
  UTC timestamp — otherwise timezone travel corrupts day boundaries.
- `targets` is **history-preserving** (`effective_from` + a row per change), not columns on
  the profile. Otherwise changing your goal in June silently rewrites January's charts.
- `amount_g` is always grams internally; the serving the user picked is stored alongside
  for re-editing.

No `favorites`/`recents` tables — favorites is a flag plus `pinned_foods`; recents is a
query over `diary_entries`.

---

## Food data pipeline

**BLS** (`tools/etl/build_bls.mjs`) — unzip, stream the XLSX via `exceljs`, map the ~28
surfaced nutrients, normalize, write `bls_foods` + FTS. Result ≈ **3 MB**.

**OFF** (`tools/etl/build_off.sql`) — **DuckDB CLI against the HuggingFace `food.parquet`**,
not Node streaming the TSV. Parquet is columnar, so predicate + projection pushdown reads a
few hundred MB instead of decompressing 9 GB; DuckDB is a single portable `.exe` and its
`sqlite` extension writes the output table directly. Turns a ~45-minute job into ~3 minutes.

Filter: region tags + non-null kcal/protein/carbs/fat + name ≥ 2 chars + sanity bounds
(kcal ≤ 950, since pure fat is 900; macro sum ≤ 105 g). Estimated **~290k rows / ~85 MB**
for DACH, ~35 MB compressed.

Three pack variants are built and published so the Settings toggle just swaps packs:
`de` (~200k), `dach` (~290k, default), `world` (aggressively trimmed).

**Blocking first step:** the ZIP's internal file list, sheet names, header captions, and
missing-value convention are not publicly documented. Before writing the BLS ETL, download,
extract to scratch, and dump the first 3 rows + all 418 headers. Missing-value handling
matters most — "0 g fat" and "fat not measured" must never be conflated. Same for the OFF
Parquet: run `DESCRIBE SELECT * FROM 'food.parquet'` first, since `product_name` is a
nested `LIST(STRUCT(lang, text))` rather than a flat column.

### Shipping

**BLS bundles into the APK** (3 MB, primary source, works offline the second you install).
**The OFF pack downloads on first run** from a GitHub Release — not because of size limits
(sideloading has none) but because it lets the food data refresh monthly without shipping a
new APK, which matters precisely because there's no store update channel. The same download
path is what the web target will need later.

A `manifest.json` carries version, URL, bytes, SHA-256, row count, and `min_app_schema` (an
old app must never load a pack shape it can't read). Install is atomic: download → verify
SHA-256 + `PRAGMA integrity_check` → close old handle → rename over. Failure leaves the old
pack live. Checked at most weekly, Wi-Fi only by default.

**Deltas are used on the build machine, never on-device.** OFF's delta window is 14 days,
so any user who skips two weeks needs a full pack anyway — on-device deltas would mean
maintaining both paths and duplicating the normalizer in Dart. A monthly GitHub Actions cron
rebuilds and publishes; the phone does full-replace. One code path.

---

## Search

**German normalization is done explicitly, not by the tokenizer.** FTS5's
`remove_diacritics 2` folds ä→a, which is wrong for German (users type "Käse" or "Kaese",
never "Kase"), and it does nothing at all for ß. So: lowercase, then ä→ae ö→oe ü→ue ß→ss,
strip other combining marks, punctuation → space. Tokenizer runs with
`remove_diacritics 0` to avoid double-folding.

This normalizer exists in two languages (Node for ETL, Dart at runtime) and **drift between
them is a silent killer** — index says `kaese`, query says `käse`, zero results. Mitigation:
one shared JSON fixture of ~50 word pairs, asserted by tests on both sides.

**Compound words** ("Vollkornbrot" must be findable by "brot"): decompose at ETL time
against a curated list of ~300–800 German food morphemes, appending matched stems to
`search_text` (`"vollkornbrot" → "vollkornbrot korn brot"`). Costs ~10 bytes/row. The
trigram tokenizer is rejected — it inflates the index 4–6× and wrecks BM25 relevance.

**Ranking:** normalize BM25 per provider, then weight by source (custom 1.10, BLS 1.00,
OFF-local 0.85, OFF-online 0.70) with boosts for exact/prefix match, completeness, and short
names. A **recency boost from your own logging history** is applied post-merge — it's the
highest-leverage ranking signal in a tracker, and it lives in the user DB. BLS outranks OFF
because BLS entries are lab-grade generics matching how people log home-cooked food; OFF
wins via barcode, not typing. BLS and OFF are never deduped against each other — generic vs
branded are semantically different and both should show with a source badge.

**Orchestrator:** debounce 250 ms, run local providers concurrently on separate isolates,
emit local results immediately, and only hit the network when local returns < 5 hits or the
user taps "Online suchen" — never per keystroke. Remote results append below a divider so
the list doesn't reshuffle under your finger.

**Barcode chain:** custom foods → `off_cache` → local pack → online API (3 s timeout,
identifying User-Agent as OFF requires) → cache the hit → else offer "Produkt selbst
anlegen" prefilled with the barcode. The cache is checked before the pack because it holds
newer data by construction, and it lives in the **user** DB so it survives pack replacement.

---

## Recipe builder with portion scaling

Modelled on [windowsaft/kalorienrechner](https://github.com/windowsaft/kalorienrechner),
which handles cooking correctly. Ingredients store per-100g values; each row has a weight
input; rows sum to a batch total; then you enter the weight of the portion you actually ate
and everything scales by `portion_weight / total_batch_weight`.

This beats fixed "servings" because cooking loses water weight — a 1,800 g pot of chili
becomes a 450 g plate and the math stays honest.

```
Zutat              Gewicht   kcal   KH    Fett  Eiweiß
Hackfleisch        500 g     1050   0     75    100
Kidneybohnen       400 g      380   60     2     26
Tomaten passiert   500 g      175   35     1      8
──────────────────────────────────────────────────────
Summe             1400 g     1605   95    78    134
Portion            450 g      516   31    25     43   ← scales live
```

The portion result logs straight into a meal.

---

## Implementation phases

`git init` first. Each phase ends in a conventional commit.

| # | Commit | Content |
|---|---|---|
| 0 | `chore: initialize repository` | git init, .gitignore, README with data-source attribution |
| 1 | — | **BLS ZIP inspection** (blocking, no commit — findings recorded in phase 2) |
| 2 | `feat: scaffold flutter app with drift and riverpod` | Project, deps, folder structure, analysis options |
| 3 | `feat(db): add user schema with sync-ready metadata` | All user tables, SyncableTable mixin, migration v1 |
| 4 | `feat(data): build bls reference database` | `build_bls.mjs`, german_normalizer + shared fixtures, bundled asset |
| 5 | `feat(search): unified food search across providers` | FoodProvider interface, orchestrator, custom + BLS providers |
| 6 | `feat(diary): daily view with four meals` | Breakfast/lunch/dinner/snacks, totals vs target |
| 7 | `feat(profile): tdee calculator with manual override` | Mifflin-St Jeor, activity factor, goal, targets history |
| 8 | `feat(hydration): water tracking with quick-add buttons` | Water log, daily goal |
| 9 | `feat(activity): manual calorie burn with safety factor` | Adds to budget × 0.8, adjustable |
| 10 | `feat(recipes): ingredient table with portion scaling` | Custom foods + recipe builder |
| 11 | `feat(data): add off product pack with download installer` | DuckDB ETL, manifest, atomic swap, region setting |
| 12 | `feat(scan): barcode scanning via mobile_scanner` | mobile_scanner (CameraX/MLKit), online fallback, cache |
| 13 | `feat(ui): favorites and quick re-log` | Pinned foods, re-log a previous entry or whole meal |
| 14 | `feat(profile): weight log with trend chart` | Weight tracking feeding TDEE |

**Phases 2–6 alone are a usable tracker** (custom foods + 7,140 German BLS foods, fully
offline). Barcode scanning is genuinely useful but comes after the core loop works.

---

## Verification

Per phase, before committing:

- `flutter analyze` clean, `dart format` applied.
- `flutter test` — unit tests for the pieces where bugs are silent rather than loud:
  the German normalizer (both-sides fixture parity), portion/recipe scaling math,
  Mifflin-St Jeor TDEE, day-boundary handling for `logged_on`, target-history resolution.
- `flutter run -d windows` for fast UI iteration; **`flutter run -d <android>` on the real
  phone** for anything touching camera, storage, or the pack download.

End-to-end acceptance, on the phone:

1. Fresh install → BLS search works offline **before** any download completes.
2. Search "vollkorn", "käse", "kaese", "Käse" → all return sensible ranked hits.
3. Log a food into each of the 4 meals; daily totals and remaining budget update.
4. Log 500 ml water and a 300 kcal activity → budget rises by 240 (0.8 factor).
5. Build a recipe, set a portion weight, log it; edit an ingredient → totals recompute.
6. Scan a real barcode from your kitchen: hits the local pack; scan an obscure import:
   falls back online, then scan it again offline (airplane mode) → served from cache.
7. Kill and relaunch → all data persists.
8. Replace the OFF pack with a new version → user data, recipes, and diary history are
   untouched, and past entries still show their original nutrient values.

Test 8 is the one that proves the two-database split works — run it deliberately.

---

## Known risks

- **BLS XLSX shape unverified** — highest uncertainty, gated by phase 1.
- **OFF Parquet nested schema** may differ from expectation; `DESCRIBE` before writing the
  query, JSONL-gz streaming as documented fallback.
- **Normalizer drift** between Node and Dart — mitigated by shared fixtures.
- **FTS5 availability** — verify `sqlite_compileoption_used('ENABLE_FTS5')` at first run;
  confirm for `sqlite3.wasm` before committing to the web path.
- **Android backup** — exclude `reference.sqlite` via `data_extraction_rules.xml`; an 85 MB
  re-downloadable file has no business in your Google backup quota.
