#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

sh tools/release/check_dependency_policy.sh
sh tools/release/check_sast_baseline.sh

if [ ! -f LICENSE ]; then
  echo "missing LICENSE file" >&2
  exit 1
fi

if ! grep -q "MIT License" LICENSE; then
  echo "LICENSE is not MIT" >&2
  exit 1
fi

if ! grep -q '\.minimum_zig_version = "0.15.2"' build.zig.zon; then
  echo "build.zig.zon minimum Zig version is not pinned to 0.15.2" >&2
  exit 1
fi

TMP_SBOM="$(mktemp "${TMPDIR:-/tmp}/zigmund-sbom-XXXXXX")"
TMP_API="$(mktemp "${TMPDIR:-/tmp}/zigmund-api-surface-XXXXXX")"
trap 'rm -f "$TMP_SBOM" "$TMP_API"' EXIT

sh tools/release/generate_api_surface.sh "$TMP_API"
if ! diff -u tools/release/api-surface-v0.txt "$TMP_API" >/dev/null; then
  echo "public api surface drift detected; update tools/release/api-surface-v0.txt intentionally" >&2
  diff -u tools/release/api-surface-v0.txt "$TMP_API" || true
  exit 1
fi

zig build run -- sbom --out "$TMP_SBOM"
if ! grep -q '"bomFormat":"CycloneDX"' "$TMP_SBOM"; then
  echo "generated sbom missing CycloneDX marker" >&2
  exit 1
fi

if ! grep -q '"id":"MIT"' "$TMP_SBOM"; then
  echo "generated sbom missing MIT license marker" >&2
  exit 1
fi

echo "governance checks passed"
