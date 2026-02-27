#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/tools/parity"
URLS_FILE="$OUT_DIR/fastapi_urls.txt"
BASELINE_FILE="$OUT_DIR/fastapi_urls.baseline.txt"

PARITY_URLS_SOURCE=remote sh "$OUT_DIR/fetch_fastapi_sitemap.sh"
cp "$URLS_FILE" "$BASELINE_FILE"
PARITY_URLS_SOURCE=baseline sh "$OUT_DIR/fetch_fastapi_sitemap.sh"

echo "updated parity baseline: $BASELINE_FILE"
