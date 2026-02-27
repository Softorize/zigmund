#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
ALLOWLIST_FILE="$ROOT_DIR/tools/release/allowed-dependencies.txt"
ZON_FILE="$ROOT_DIR/build.zig.zon"

if [ ! -f "$ALLOWLIST_FILE" ]; then
  echo "missing dependency allowlist file: $ALLOWLIST_FILE" >&2
  exit 1
fi

TMP_DEPS="$(mktemp "${TMPDIR:-/tmp}/zigmund-zon-deps-XXXXXX")"
TMP_DEPS_RAW="$(mktemp "${TMPDIR:-/tmp}/zigmund-zon-deps-raw-XXXXXX")"
TMP_ALLOW="$(mktemp "${TMPDIR:-/tmp}/zigmund-allowed-deps-XXXXXX")"
trap 'rm -f "$TMP_DEPS" "$TMP_DEPS_RAW" "$TMP_ALLOW"' EXIT

awk '
  BEGIN {
    in_deps = 0
    depth = 0
  }

  function count_char(input, needle,  n, i, c) {
    n = length(input)
    c = 0
    for (i = 1; i <= n; i++) {
      if (substr(input, i, 1) == needle) c++
    }
    return c
  }

  {
    if (!in_deps) {
      if ($0 ~ /^[[:space:]]*\.dependencies[[:space:]]*=[[:space:]]*\./) {
        in_deps = 1
        depth = count_char($0, "{") - count_char($0, "}")
        if (depth <= 0) {
          in_deps = 0
          depth = 0
        }
      }
      next
    }

    if (depth == 1) {
      line = $0
      sub(/^[[:space:]]*\./, "", line)
      sub(/[[:space:]]*=.*/, "", line)
      if (line ~ /^[A-Za-z0-9_-][A-Za-z0-9_-]*$/) print line
    }

    depth += count_char($0, "{")
    depth -= count_char($0, "}")
    if (depth <= 0) {
      in_deps = 0
      depth = 0
    }
  }
' "$ZON_FILE" > "$TMP_DEPS_RAW"

sort -u "$TMP_DEPS_RAW" > "$TMP_DEPS"

grep -v '^[[:space:]]*$' "$ALLOWLIST_FILE" | grep -v '^[[:space:]]*#' | sort -u > "$TMP_ALLOW" || true

missing=0
while IFS= read -r dep; do
  [ -z "$dep" ] && continue
  if ! grep -Fxq "$dep" "$TMP_ALLOW"; then
    echo "dependency policy violation: '$dep' is not listed in $ALLOWLIST_FILE" >&2
    missing=1
  fi
done < "$TMP_DEPS"

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "dependency policy checks passed"
