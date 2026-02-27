#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
OUT_PATH="${1:-$ROOT_DIR/tools/release/api-surface-current.txt}"

cd "$ROOT_DIR"

rg -n '^pub (const|fn) ' src/zigmund.zig \
  | sed -E 's/^[0-9]+:pub (const|fn) ([A-Za-z0-9_]+).*/\2/' \
  | sort -u > "$OUT_PATH"

echo "wrote $OUT_PATH"
