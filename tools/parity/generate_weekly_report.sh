#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist/reports/parity-weekly}"
SUMMARY_FILE="$ROOT_DIR/tools/parity/parity-summary.json"
MATRIX_FILE="$ROOT_DIR/tools/parity/parity-matrix.md"

mkdir -p "$OUT_DIR"

cleanup() {
  PARITY_URLS_SOURCE=baseline sh "$ROOT_DIR/tools/parity/fetch_fastapi_sitemap.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

extract_field() {
  file="$1"
  key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" "$file" | head -n1
}

PARITY_URLS_SOURCE=baseline sh "$ROOT_DIR/tools/parity/fetch_fastapi_sitemap.sh"
cp "$SUMMARY_FILE" "$OUT_DIR/summary-baseline.json"
cp "$MATRIX_FILE" "$OUT_DIR/matrix-baseline.md"

baseline_total="$(extract_field "$OUT_DIR/summary-baseline.json" total)"
baseline_implemented="$(extract_field "$OUT_DIR/summary-baseline.json" implemented)"
baseline_stub="$(extract_field "$OUT_DIR/summary-baseline.json" stub)"
baseline_missing="$(extract_field "$OUT_DIR/summary-baseline.json" missing)"

PARITY_URLS_SOURCE=remote sh "$ROOT_DIR/tools/parity/fetch_fastapi_sitemap.sh"
cp "$SUMMARY_FILE" "$OUT_DIR/summary-remote.json"
cp "$MATRIX_FILE" "$OUT_DIR/matrix-remote.md"

remote_total="$(extract_field "$OUT_DIR/summary-remote.json" total)"
remote_implemented="$(extract_field "$OUT_DIR/summary-remote.json" implemented)"
remote_stub="$(extract_field "$OUT_DIR/summary-remote.json" stub)"
remote_missing="$(extract_field "$OUT_DIR/summary-remote.json" missing)"

delta_total=$((remote_total - baseline_total))
delta_missing=$((remote_missing - baseline_missing))

cat > "$OUT_DIR/report.json" <<EOF
{"baseline":{"total":$baseline_total,"implemented":$baseline_implemented,"stub":$baseline_stub,"missing":$baseline_missing},"remote":{"total":$remote_total,"implemented":$remote_implemented,"stub":$remote_stub,"missing":$remote_missing},"delta":{"total":$delta_total,"missing":$delta_missing}}
EOF

echo "wrote weekly parity report to $OUT_DIR"
