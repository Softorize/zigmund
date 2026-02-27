#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

scan_paths="src tests tools docs"

if rg -n --fixed-strings "-----BEGIN PRIVATE KEY-----" $scan_paths >/dev/null 2>&1; then
  echo "sast baseline failed: detected private key marker" >&2
  rg -n --fixed-strings "-----BEGIN PRIVATE KEY-----" $scan_paths || true
  exit 1
fi

if rg -n -e 'AKIA[0-9A-Z]{16}' $scan_paths >/dev/null 2>&1; then
  echo "sast baseline failed: detected AWS access key pattern" >&2
  rg -n -e 'AKIA[0-9A-Z]{16}' $scan_paths || true
  exit 1
fi

if rg -n --fixed-strings "-----BEGIN RSA PRIVATE KEY-----" $scan_paths >/dev/null 2>&1; then
  echo "sast baseline failed: detected RSA private key marker" >&2
  rg -n --fixed-strings "-----BEGIN RSA PRIVATE KEY-----" $scan_paths || true
  exit 1
fi

echo "sast baseline checks passed"
