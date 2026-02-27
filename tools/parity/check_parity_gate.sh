#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
SUMMARY_FILE="$ROOT_DIR/tools/parity/parity-summary.json"

sh "$ROOT_DIR/tools/parity/fetch_fastapi_sitemap.sh"

if [ ! -f "$SUMMARY_FILE" ]; then
  echo "missing parity summary file: $SUMMARY_FILE" >&2
  exit 1
fi

extract_field() {
  key="$1"
  sed -n "s/.*\"$key\":\\([0-9][0-9]*\\).*/\\1/p" "$SUMMARY_FILE"
}

total="$(extract_field total)"
implemented="$(extract_field implemented)"
stub="$(extract_field stub)"
missing="$(extract_field missing)"

if [ -z "$total" ] || [ -z "$implemented" ] || [ -z "$stub" ] || [ -z "$missing" ]; then
  echo "failed to parse parity summary values from $SUMMARY_FILE" >&2
  exit 1
fi

required_implemented="${PARITY_REQUIRED_IMPLEMENTED:-$total}"
max_stub="${PARITY_MAX_STUB:-$total}"
max_missing="${PARITY_MAX_MISSING:-0}"

if [ "$implemented" -lt "$required_implemented" ]; then
  echo "parity gate failed: implemented=$implemented required>=$required_implemented" >&2
  exit 1
fi

if [ "$stub" -gt "$max_stub" ]; then
  echo "parity gate failed: stub=$stub max=$max_stub" >&2
  exit 1
fi

if [ "$missing" -gt "$max_missing" ]; then
  echo "parity gate failed: missing=$missing max=$max_missing" >&2
  exit 1
fi

enforce_contract="${PARITY_ENFORCE_CONTRACT:-1}"
if [ "$enforce_contract" = "1" ]; then
  sh "$ROOT_DIR/tools/parity/check_examples_contract.sh"
fi

echo "parity gate passed: implemented=$implemented/$total stub=$stub missing=$missing"
