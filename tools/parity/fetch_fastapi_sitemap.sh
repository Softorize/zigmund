#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/tools/parity"
URLS_FILE="$OUT_DIR/fastapi_urls.txt"
BASELINE_FILE="$OUT_DIR/fastapi_urls.baseline.txt"
MATRIX_FILE="$OUT_DIR/parity-matrix.md"
SUMMARY_FILE="$OUT_DIR/parity-summary.json"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
SOURCE="${PARITY_URLS_SOURCE:-baseline}"

mkdir -p "$OUT_DIR"

case "$SOURCE" in
  baseline)
    if [ ! -f "$BASELINE_FILE" ]; then
      echo "missing parity baseline file: $BASELINE_FILE" >&2
      exit 1
    fi
    cp "$BASELINE_FILE" "$URLS_FILE"
    ;;
  remote)
    curl -fsSL https://fastapi.tiangolo.com/sitemap.xml \
      | grep -o '<loc>[^<]*' \
      | sed 's#<loc>##' \
      | grep -E '^https://fastapi\.tiangolo\.com/(tutorial|advanced|reference|how-to)/' \
      | sed 's#https://fastapi\.tiangolo\.com/##' \
      | sort > "$URLS_FILE"
    ;;
  local)
    if [ ! -f "$URLS_FILE" ]; then
      echo "missing local parity urls file: $URLS_FILE" >&2
      exit 1
    fi
    ;;
  *)
    echo "invalid PARITY_URLS_SOURCE '$SOURCE' (expected: baseline|remote|local)" >&2
    exit 1
    ;;
esac

total_count="$(wc -l < "$URLS_FILE" | tr -d ' ')"
implemented_count=0
stub_count=0
missing_count=0

{
  printf '# FastAPI Parity Matrix\n\n'
  printf 'Generated: %s\n\n' "$GENERATED_AT"
  printf 'Total docs targets: %s\n\n' "$total_count"
  printf '| FastAPI Doc Path | Zigmund Example | Status |\n'
  printf '|---|---|---|\n'

  while IFS= read -r doc_path; do
    category="$(printf '%s' "$doc_path" | cut -d'/' -f1)"
    remainder="$(printf '%s' "$doc_path" | cut -d'/' -f2- | sed 's#/$##')"

    if [ -z "$remainder" ]; then
      slug="index"
    else
      slug="$(printf '%s' "$remainder" | sed 's#/#__#g')"
    fi

    example_rel="examples/parity/${category}/${slug}.zig"
    example_abs="$ROOT_DIR/$example_rel"

    if [ -f "$example_abs" ]; then
      if grep -q 'ZIGMUND_PARITY_STUB' "$example_abs"; then
        status='stub'
        stub_count=$((stub_count + 1))
      else
        status='implemented'
        implemented_count=$((implemented_count + 1))
      fi
    else
      status='missing'
      missing_count=$((missing_count + 1))
    fi

    printf '| `%s` | `%s` | %s |\n' "$doc_path" "$example_rel" "$status"
  done < "$URLS_FILE"

  printf '\nImplemented: %s/%s\n' "$implemented_count" "$total_count"
  printf 'Stub: %s/%s\n' "$stub_count" "$total_count"
  printf 'Missing: %s/%s\n' "$missing_count" "$total_count"
} > "$MATRIX_FILE"

cat > "$SUMMARY_FILE" <<EOF
{"generated_at":"$GENERATED_AT","total":$total_count,"implemented":$implemented_count,"stub":$stub_count,"missing":$missing_count}
EOF

printf 'Wrote %s, %s, and %s\n' "$URLS_FILE" "$MATRIX_FILE" "$SUMMARY_FILE"
