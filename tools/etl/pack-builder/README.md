# OFF pack builder

A self-contained container that rebuilds the Open Food Facts product pack on a
schedule and publishes it to a rolling GitHub Release. Runs on your own server
(where the multi-GB dump and DuckDB live); GitHub's CDN serves the download, so
you pay no egress and run no web server.

## What it does, each scheduled run

1. Refresh the cached OFF dump (`food.parquet`) if it's missing or older than
   `MAX_DUMP_AGE_DAYS`.
2. For **each** region in `REGIONS` (default `de dach world`):
   `duckdb` filters the dump to that region → `off_products.ndjson`
   (`build_off.sql`, region set via a variable), then `node build_off.mjs`
   normalizes it and writes `off_<region>.sqlite`, merging its entry into the
   single `manifest.json`.
3. `gh` uploads every pack **first**, the manifest **last**, all `--clobber`,
   to the `off-latest` release. Publish-order means a client never verifies a
   manifest against a half-uploaded pack.

The dump and build outputs live on the `/data` volume, so container restarts
reuse the cached dump instead of re-downloading it.

## Setup

```sh
cd tools/etl/pack-builder
cp .env.example .env          # fill in GH_TOKEN (fine-grained PAT, contents:write)
docker compose up -d --build
```

The schedule (quarterly by default) is now active. To publish immediately —
first-ever pack, or a test — do one run with `RUN_ON_START=true`:

```sh
RUN_ON_START=true docker compose up -d --build
docker compose logs -f        # watch the build
```

Then bring it back up without the flag so it only runs on schedule.

Trigger an ad-hoc build any time without restarting:

```sh
docker compose exec off-pack-builder /app/build-and-publish.sh
```

## Configuration

All via `.env` (see `.env.example`): `GH_TOKEN`, `REPO`, `RELEASE_TAG`,
`REGIONS`, `CRON_SCHEDULE`, `MAX_DUMP_AGE_DAYS`, `NODE_HEAP_MB`, `RUN_ON_START`.

## Requirements & caveats

- **amd64 host.** The pinned DuckDB and gh binaries are `linux-amd64`; on arm64
  change the URLs in the `Dockerfile`.
- **Disk.** The volume holds the dump (several GB) + the NDJSON intermediate +
  one `.sqlite` per region. Give `/data` comfortable headroom.
- **`world` is heavy.** It's the entire database with no country filter — many
  times the size of `dach`. The build loads all valid products into memory
  before writing, so it needs a roomy `NODE_HEAP_MB` and host RAM, and it
  produces a large download (a real consideration for a mobile app). Drop
  `world` from `REGIONS` if you don't need it. If it OOMs even with more heap,
  the fix is a streaming DB insert in `build_off.mjs` (not yet implemented).
- **Token.** A fine-grained PAT scoped to *Contents: read and write* on the
  packs repo. Store it only in `.env` (gitignored).
- **Repo must exist on GitHub.** The release/upload target
  (`REPO`) has to be pushed first.
- **Schema drift.** OFF occasionally changes the parquet layout;
  `build_off.sql` has a `DESCRIBE` check at the top. If a run fails in the
  DuckDB step, reconcile the column/struct names there.

## App side

The app reads the manifest from a single URL. Point its default at this
release once (`lib/data/pack/pack_service.dart`, the `defaultManifestUrl`):

```
https://github.com/windowsaft/easytrack/releases/download/off-latest/manifest.json
```
