#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <nightly|alpha|beta|rc|stable>" >&2
  exit 1
fi

channel="$1"

case "$channel" in
  nightly|alpha|beta|rc|stable)
    ;;
  *)
    echo "invalid release channel: $channel" >&2
    exit 1
    ;;
esac

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [ -n "${PERF_GATE_MODE:-}" ]; then
  perf_mode="$PERF_GATE_MODE"
else
  case "$channel" in
    rc|stable)
      perf_mode="strict"
      ;;
    *)
      perf_mode="shared"
      ;;
  esac
fi

echo "release pipeline start: channel=$channel perf_mode=$perf_mode"

zig build test
sh tools/parity/check_parity_gate.sh
PERF_GATE_MODE="$perf_mode" sh tools/perf/run_perf_suite.sh
sh tools/release/check_governance.sh

release_ref="${RELEASE_REF:-}"
if [ -z "$release_ref" ]; then
  release_ref="$(git rev-parse --abbrev-ref HEAD)"
fi

RELEASE_CHANNEL="$channel" RELEASE_REF="$release_ref" \
  sh tools/release/build_release_artifacts.sh

echo "release pipeline complete: channel=$channel"
