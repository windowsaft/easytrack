#!/usr/bin/env bash
# Container entrypoint: wire the volume into the ETL scripts' expected paths,
# hand the runtime config to cron (cron jobs do NOT inherit container env), then
# run cron in the foreground as PID 1.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required (fine-grained PAT with contents:write on the repo)}"
REPO="${REPO:-windowsaft/easytrack}"
RELEASE_TAG="${RELEASE_TAG:-off-latest}"
REGIONS="${REGIONS:-de dach world}"
NODE_HEAP_MB="${NODE_HEAP_MB:-6144}"
DUMP_URL="${DUMP_URL:-https://huggingface.co/datasets/openfoodfacts/product-database/resolve/main/food.parquet}"
MAX_DUMP_AGE_DAYS="${MAX_DUMP_AGE_DAYS:-80}"
# 03:00 on the 1st of Jan / Apr / Jul / Oct.
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 1 1,4,7,10 *}"
RUN_ON_START="${RUN_ON_START:-false}"
DATA_DIR=/data

mkdir -p "$DATA_DIR/dist"

# build_off.sql reads ./food.parquet and writes tools/etl/dist/… (cwd-relative
# from /app); build_off.mjs defaults its DIST_DIR to <here>/dist. Symlinking
# both onto the volume lets the unmodified scripts read the cached dump and
# write their outputs to persistent storage.
ln -sfn "$DATA_DIR/dist" /app/tools/etl/dist
ln -sfn "$DATA_DIR/food.parquet" /app/food.parquet

# Freeze the config into a file the cron-invoked build sources. PATH is set
# explicitly because cron's default (/usr/bin:/bin) omits /usr/local/bin, where
# node, gh and duckdb live.
cat > /app/pack-builder.env <<EOF
export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export GH_TOKEN='${GH_TOKEN}'
export REPO='${REPO}'
export RELEASE_TAG='${RELEASE_TAG}'
export REGIONS='${REGIONS}'
export NODE_HEAP_MB='${NODE_HEAP_MB}'
export DUMP_URL='${DUMP_URL}'
export MAX_DUMP_AGE_DAYS='${MAX_DUMP_AGE_DAYS}'
export DATA_DIR='${DATA_DIR}'
EOF
chmod 0600 /app/pack-builder.env

# Install the schedule. Output is redirected to PID 1's stdout (this cron, after
# the exec below) so every run shows up in `docker logs`.
echo "${CRON_SCHEDULE} root . /app/pack-builder.env; /app/build-and-publish.sh >> /proc/1/fd/1 2>&1" \
  > /etc/cron.d/pack-builder
chmod 0644 /etc/cron.d/pack-builder

echo "pack-builder ready — schedule='${CRON_SCHEDULE}' regions='${REGIONS}' repo='${REPO}' tag='${RELEASE_TAG}'"

# Optional immediate build (first publish / testing) without waiting for the
# first scheduled tick.
if [ "${RUN_ON_START}" = "true" ]; then
  echo "RUN_ON_START=true — building once now"
  ( set +e; . /app/pack-builder.env; /app/build-and-publish.sh ) \
    || echo "initial build failed (see log above); the schedule is still active"
fi

exec cron -f
