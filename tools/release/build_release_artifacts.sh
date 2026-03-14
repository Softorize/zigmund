#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-dev}"
RELEASE_REF="${RELEASE_REF:-}"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
COMMIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
COSIGN_SIGN_RELEASES="${COSIGN_SIGN_RELEASES:-auto}"

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

SIGN_RELEASES=false
if [ "$COSIGN_SIGN_RELEASES" = "true" ]; then
  SIGN_RELEASES=true
elif [ "$COSIGN_SIGN_RELEASES" = "auto" ] && [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  SIGN_RELEASES=true
fi

if [ "$SIGN_RELEASES" = "true" ] && ! command -v cosign >/dev/null 2>&1; then
  echo "cosign is required when COSIGN_SIGN_RELEASES=$COSIGN_SIGN_RELEASES" >&2
  exit 1
fi

shasum -a 256 "$BIN_DST" > "$BIN_DST.sha256"
shasum -a 256 "$DIST_DIR/zigmund.sbom.json" > "$DIST_DIR/zigmund.sbom.json.sha256"

cat > "$DIST_DIR/release-metadata.json" <<EOF
{"generated_at":"$GENERATED_AT","channel":"$RELEASE_CHANNEL","ref":"$RELEASE_REF","commit":"$COMMIT_SHA","os":"$OS_NAME","arch":"$ARCH_NAME","binary":"$(basename "$BIN_DST")","sbom":"zigmund.sbom.json","signed":$SIGN_RELEASES}
EOF
shasum -a 256 "$DIST_DIR/release-metadata.json" > "$DIST_DIR/release-metadata.json.sha256"

if [ "$SIGN_RELEASES" = "true" ]; then
  for artifact in \
    "$BIN_DST" \
    "$DIST_DIR/zigmund.sbom.json" \
    "$DIST_DIR/release-metadata.json"
  do
    cosign sign-blob \
      --yes \
      --output-signature "$artifact.sig" \
      --output-certificate "$artifact.pem" \
      "$artifact"
  done
fi

echo "release artifacts written to $DIST_DIR"
