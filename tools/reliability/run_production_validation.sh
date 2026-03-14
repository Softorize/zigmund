#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/reliability"
EVIDENCE_FILE="$DIST_DIR/production-validation.json"
SOAK_CONNECTIONS="${ZIGMUND_SOAK_CONNECTIONS:-500}"
SOAK_ROUNDS="${ZIGMUND_SOAK_ROUNDS:-3}"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
COMMIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

mkdir -p "$DIST_DIR"
cd "$ROOT_DIR"

if [ "$SOAK_CONNECTIONS" -lt 1 ] || [ "$SOAK_ROUNDS" -lt 1 ]; then
  echo "soak parameters must be positive integers" >&2
  exit 1
fi

echo "running runtime soak suite: rounds=$SOAK_ROUNDS connections=$SOAK_CONNECTIONS"
ZIGMUND_SOAK_MODE=1 \
ZIGMUND_SOAK_CONNECTIONS="$SOAK_CONNECTIONS" \
ZIGMUND_SOAK_ROUNDS="$SOAK_ROUNDS" \
  zig build soak

echo "running deploy dry-run validations"
zig build run -- cloud --provider docker --execute --dry-run --image zigmund:soak-validation > "$DIST_DIR/cloud-docker-dry-run.txt"
zig build run -- cloud --provider flyio --execute --dry-run > "$DIST_DIR/cloud-flyio-dry-run.txt"

cat > "$EVIDENCE_FILE" <<JSON
{"generated_at":"$GENERATED_AT","commit":"$COMMIT_SHA","soak":{"mode":true,"rounds":$SOAK_ROUNDS,"connections":$SOAK_CONNECTIONS},"deploy_validation":{"docker_dry_run":"dist/reliability/cloud-docker-dry-run.txt","flyio_dry_run":"dist/reliability/cloud-flyio-dry-run.txt"},"status":"passed"}
JSON

echo "production validation evidence written to $EVIDENCE_FILE"
