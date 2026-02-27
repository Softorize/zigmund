#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/docs/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "missing docs/migrations directory" >&2
  exit 1
fi

count="$(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '20*.md' | wc -l | tr -d ' ')"
if [ "$count" -eq 0 ]; then
  echo "missing dated migration notes in docs/migrations (expected at least one 20*.md file)" >&2
  exit 1
fi

for file in "$MIGRATIONS_DIR"/20*.md; do
  if ! grep -q '^# ' "$file"; then
    echo "migration note missing top-level heading: $file" >&2
    exit 1
  fi
done

echo "migration notes checks passed"
