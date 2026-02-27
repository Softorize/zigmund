#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CONCEPTS_FILE="$ROOT_DIR/tools/parity/fastapi-core-concepts.tsv"
OUT_FILE="${1:-$ROOT_DIR/tools/parity/api-parity-summary.json}"
TMP_EXPORTS="$(mktemp "${TMPDIR:-/tmp}/zigmund-exports-XXXXXX")"
trap 'rm -f "$TMP_EXPORTS"' EXIT

if [ ! -f "$CONCEPTS_FILE" ]; then
  echo "missing concepts file: $CONCEPTS_FILE" >&2
  exit 1
fi

cd "$ROOT_DIR"

rg -n '^pub (const|fn) ' src/zigmund.zig \
  | sed -E 's/^[0-9]+:pub (const|fn) ([A-Za-z0-9_]+).*/\2/' \
  | sort -u > "$TMP_EXPORTS"

total=0
implemented=0
missing=0
entries=""
first=1

while IFS='|' read -r concept symbol; do
  # Skip empty/comment lines.
  [ -z "${concept}" ] && continue
  case "$concept" in
    \#*) continue ;;
  esac

  total=$((total + 1))
  status="implemented"
  if grep -Fxq "$symbol" "$TMP_EXPORTS"; then
    implemented=$((implemented + 1))
  else
    status="missing"
    missing=$((missing + 1))
  fi

  if [ "$first" -eq 0 ]; then
    entries="${entries},"
  fi
  first=0
  entries="${entries}{\"concept\":\"${concept}\",\"zigmund_symbol\":\"${symbol}\",\"status\":\"${status}\"}"
done < "$CONCEPTS_FILE"

cat > "$OUT_FILE" <<JSON
{"total":$total,"implemented":$implemented,"missing":$missing,"entries":[${entries}]}
JSON

if [ "$missing" -gt 0 ]; then
  echo "api parity gate failed: implemented=$implemented/$total missing=$missing" >&2
  exit 1
fi

echo "api parity gate passed: implemented=$implemented/$total missing=$missing"
echo "wrote $OUT_FILE"
