#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
URLS_FILE="$ROOT_DIR/tools/parity/fastapi_urls.txt"

if [ ! -f "$URLS_FILE" ]; then
  sh "$ROOT_DIR/tools/parity/fetch_fastapi_sitemap.sh"
fi

errors=0
checked=0

while IFS= read -r doc_path; do
  category="$(printf '%s' "$doc_path" | cut -d'/' -f1)"
  remainder="$(printf '%s' "$doc_path" | cut -d'/' -f2- | sed 's#/$##')"

  if [ -z "$remainder" ]; then
    slug="index"
  else
    slug="$(printf '%s' "$remainder" | sed 's#/#__#g')"
  fi

  example_file="$ROOT_DIR/examples/parity/${category}/${slug}.zig"
  if [ ! -f "$example_file" ]; then
    # Missing files are checked by parity-matrix gate.
    continue
  fi

  checked=$((checked + 1))

  if grep -q 'ZIGMUND_PARITY_STUB' "$example_file"; then
    echo "contract failed (stub marker present): $example_file" >&2
    errors=$((errors + 1))
    continue
  fi

  if ! grep -q 'pub fn buildExample(app: \*zigmund.App) !void' "$example_file"; then
    echo "contract failed (missing buildExample signature): $example_file" >&2
    errors=$((errors + 1))
  fi

  if ! grep -E -q 'try app\.(get|post|put|patch|delete|options|head|trace|websocket|includeRouter|mount)\(' "$example_file"; then
    echo "contract failed (missing app route wiring): $example_file" >&2
    errors=$((errors + 1))
  fi
done < "$URLS_FILE"

if [ "$errors" -ne 0 ]; then
  echo "parity example contract checks failed: errors=$errors checked=$checked" >&2
  exit 1
fi

echo "parity example contract checks passed: checked=$checked"
