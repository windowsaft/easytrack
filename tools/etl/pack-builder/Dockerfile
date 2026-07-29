# OFF product-pack builder.
#
# A self-contained, install-and-forget container: an internal cron fires the
# build on a schedule (quarterly by default), which filters the Open Food Facts
# dump with DuckDB, writes the pack + manifest with the repo's own ETL scripts,
# and uploads them to a rolling GitHub Release with the gh CLI.
#
# Build context is tools/etl (so the ETL sources are reachable); the Dockerfile
# lives in pack-builder/. See docker-compose.yml for the wired-up invocation.
FROM node:20-bookworm-slim

# Pin the two external CLIs so a rebuild reproduces the same toolchain.
ARG DUCKDB_VERSION=1.1.3
ARG GH_VERSION=2.63.2

# python3 + build-essential are here so better-sqlite3 can compile if no
# prebuilt binary matches; cron is the scheduler; unzip/curl fetch the CLIs.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip cron python3 build-essential \
    && rm -rf /var/lib/apt/lists/*

# DuckDB CLI (static single binary).
RUN curl -fsSL -o /tmp/duckdb.zip \
      "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip" \
    && unzip -o /tmp/duckdb.zip -d /usr/local/bin \
    && rm /tmp/duckdb.zip \
    && duckdb --version

# GitHub CLI.
RUN curl -fsSL -o /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64" \
    && gh --version

WORKDIR /app/tools/etl

# Node deps first so the layer caches across ETL-source edits. better-sqlite3
# links against this platform here, not the phone's.
COPY package.json package-lock.json ./
RUN npm ci

# The ETL sources the build actually runs. off_seed.json is intentionally left
# out: production feeds the DuckDB-extracted JSON, never the dev seed.
COPY build_off.mjs build_off.sql normalize.mjs de_food_morphemes.txt ./

# Builder scripts.
COPY pack-builder/entrypoint.sh pack-builder/build-and-publish.sh /app/
RUN chmod +x /app/entrypoint.sh /app/build-and-publish.sh

WORKDIR /app

# Cached dump + build outputs live here; mount a named volume or host path.
VOLUME ["/data"]

ENTRYPOINT ["/app/entrypoint.sh"]
