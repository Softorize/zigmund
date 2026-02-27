#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"

mkdir -p "$DIST_DIR"

cd "$ROOT_DIR"

zig build -Doptimize=ReleaseFast
zig build run -- sbom --out "$DIST_DIR/zigmund.sbom.json"

OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_NAME="$(uname -m | tr '[:upper:]' '[:lower:]')"

BIN_SRC="$ROOT_DIR/zig-out/bin/zigmund"
BIN_DST="$DIST_DIR/zigmund-${OS_NAME}-${ARCH_NAME}"

cp "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"

shasum -a 256 "$BIN_DST" > "$BIN_DST.sha256"
shasum -a 256 "$DIST_DIR/zigmund.sbom.json" > "$DIST_DIR/zigmund.sbom.json.sha256"

echo "release artifacts written to $DIST_DIR"
