#!/usr/bin/env bash
# Build the OFF product packs for every configured region and publish them to
# the rolling GitHub Release.
#
# Steps: refresh the cached dump → for each region { DuckDB extract → normalize
# + write pack, merging into one manifest } → upload every pack, then the
# manifest last. Any failure aborts before the upload, so a broken run never
# replaces good published packs.
set -euo pipefail

# When cron invokes us the environment is bare; the entrypoint froze the config
# here. Harmless when the vars are already set (RUN_ON_START / manual run).
[ -f /app/pack-builder.env ] && . /app/pack-builder.env

: "${GH_TOKEN:?GH_TOKEN not set}"; export GH_TOKEN
REPO="${REPO:-windowsaft/easytrack}"
RELEASE_TAG="${RELEASE_TAG:-off-latest}"
REGIONS="${REGIONS:-de dach world}"
MAX_DUMP_AGE_DAYS="${MAX_DUMP_AGE_DAYS:-80}"
# World holds the whole database in memory while building; give Node room.
NODE_HEAP_MB="${NODE_HEAP_MB:-6144}"
DATA_DIR="${DATA_DIR:-/data}"

DUMP="${DATA_DIR}/food.parquet"
DIST="${DATA_DIR}/dist"
NDJSON="${DIST}/off_products.ndjson"
MANIFEST="${DIST}/manifest.json"
# Manifest URLs point at the rolling release's stable asset paths.
BASE_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"
VERSION="$(date -u +%Y-%m-%d)"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "=== OFF pack build start (regions='${REGIONS}', version=${VERSION}) ==="

# 1. Refresh the dump only when missing or past the freshness window. A stale
#    partial from an aborted download is discarded so we never resume across a
#    changed upstream file.
if [ -f "$DUMP" ] && [ -z "$(find "$DUMP" -mtime "+${MAX_DUMP_AGE_DAYS}" -print -quit)" ]; then
  log "dump is fresh ($(du -h "$DUMP" | cut -f1)); skipping download"
else
  log "downloading dump: ${DUMP_URL}"
  rm -f "${DUMP}.part"
  curl -fSL --retry 3 --retry-delay 15 -o "${DUMP}.part" "$DUMP_URL"
  mv -f "${DUMP}.part" "$DUMP"
  log "dump downloaded ($(du -h "$DUMP" | cut -f1))"
fi

# The manifest accumulates across regions (build_off.mjs merges into it), so
# start each full run from a clean slate.
rm -f "$MANIFEST"
mkdir -p "${DATA_DIR}/duckdb-tmp"

packs=()
for region in $REGIONS; do
  log "--- region '${region}': DuckDB extraction ---"
  # build_off.sql uses cwd-relative paths (./food.parquet, tools/etl/dist/…),
  # both symlinked to the volume by the entrypoint, so run it from /app. The
  # region variable drives its WHERE filter.
  cd /app
  rm -f "$NDJSON"
  printf "SET temp_directory='%s';\nSET VARIABLE region='%s';\n.read tools/etl/build_off.sql\n" \
    "${DATA_DIR}/duckdb-tmp" "$region" | duckdb

  log "--- region '${region}': build pack + merge manifest ---"
  cd /app/tools/etl
  NODE_OPTIONS="--max-old-space-size=${NODE_HEAP_MB}" node build_off.mjs \
    --region "$region" \
    --seed "$NDJSON" \
    --base-url "$BASE_URL" \
    --version "$VERSION"

  pack="${DIST}/off_${region}.sqlite"
  [ -f "$pack" ] || { log "ERROR: pack not produced at $pack"; exit 1; }
  log "region '${region}' pack: $(du -h "$pack" | cut -f1)"
  packs+=("$pack")
done

[ -f "$MANIFEST" ] || { log "ERROR: manifest not produced at $MANIFEST"; exit 1; }

# Publish. Create the rolling release once, then upload every pack FIRST and the
# manifest LAST so a client never fetches a manifest referencing a pack that is
# still uploading. --clobber replaces each asset while keeping its URL.
log "publishing ${#packs[@]} pack(s) to ${REPO} @ ${RELEASE_TAG}"
if ! gh release view "$RELEASE_TAG" -R "$REPO" >/dev/null 2>&1; then
  log "release ${RELEASE_TAG} does not exist yet; creating it"
  gh release create "$RELEASE_TAG" -R "$REPO" \
    --title "OFF product packs" \
    --notes "Rolling Open Food Facts product packs. Assets are replaced in place; download URLs stay stable."
fi
for pack in "${packs[@]}"; do
  gh release upload "$RELEASE_TAG" "$pack" -R "$REPO" --clobber
done
gh release upload "$RELEASE_TAG" "$MANIFEST" -R "$REPO" --clobber

log "=== done: published ${#packs[@]} pack(s) + manifest.json (version ${VERSION}) ==="
