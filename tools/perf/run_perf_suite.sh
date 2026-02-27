#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

sh "$ROOT_DIR/tools/perf/collect_metrics.sh"
PERF_GATE_MODE="${PERF_GATE_MODE:-shared}" \
  sh "$ROOT_DIR/tools/perf/check_perf_regression.sh"
