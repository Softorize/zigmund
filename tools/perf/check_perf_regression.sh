#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
LATEST_FILE="$ROOT_DIR/tools/perf/latest.json"
ZIGMUND_BASELINE="$ROOT_DIR/tools/perf/baseline-zigmund.json"
FASTAPI_BASELINE="$ROOT_DIR/tools/perf/baseline-fastapi-uvicorn.json"
PERF_GATE_MODE="${PERF_GATE_MODE:-shared}"

if [ ! -f "$LATEST_FILE" ]; then
  echo "missing latest perf metrics file: $LATEST_FILE" >&2
  exit 1
fi

if [ ! -f "$ZIGMUND_BASELINE" ]; then
  echo "missing zigmund perf baseline file: $ZIGMUND_BASELINE" >&2
  exit 1
fi

if [ ! -f "$FASTAPI_BASELINE" ]; then
  echo "missing fastapi perf baseline file: $FASTAPI_BASELINE" >&2
  exit 1
fi

extract_number() {
  file="$1"
  key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9.]*\\).*/\\1/p" "$file" | head -n1
}

latest_micro="$(extract_number "$LATEST_FILE" micro_throughput_rps)"
latest_mixed="$(extract_number "$LATEST_FILE" mixed_throughput_rps)"
latest_p99="$(extract_number "$LATEST_FILE" tail_p99_us)"

base_micro="$(extract_number "$ZIGMUND_BASELINE" micro_throughput_rps)"
base_mixed="$(extract_number "$ZIGMUND_BASELINE" mixed_throughput_rps)"
base_p99="$(extract_number "$ZIGMUND_BASELINE" tail_p99_us)"

fastapi_micro="$(extract_number "$FASTAPI_BASELINE" micro_throughput_rps)"
fastapi_p99="$(extract_number "$FASTAPI_BASELINE" tail_p99_us)"

for value in \
  "$latest_micro" "$latest_mixed" "$latest_p99" \
  "$base_micro" "$base_mixed" "$base_p99" \
  "$fastapi_micro" "$fastapi_p99"; do
  if [ -z "$value" ]; then
    echo "failed to parse numeric perf metrics from baseline/latest files" >&2
    exit 1
  fi
done

lt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'
}

gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}

# Shared CI is noisier than dedicated benchmark hardware.
# Use strict enterprise thresholds only in dedicated mode.
case "$PERF_GATE_MODE" in
  strict)
    throughput_regression_multiplier="0.97"
    p99_regression_multiplier="1.05"
    fastapi_throughput_multiplier="5.0"
    fastapi_p99_multiplier="0.40"
    ;;
  shared)
    throughput_regression_multiplier="0.90"
    p99_regression_multiplier="1.20"
    fastapi_throughput_multiplier="4.0"
    fastapi_p99_multiplier="0.60"
    ;;
  *)
    echo "invalid PERF_GATE_MODE '$PERF_GATE_MODE' (expected: shared|strict)" >&2
    exit 1
    ;;
esac

micro_regression_floor="$(awk -v v="$base_micro" -v m="$throughput_regression_multiplier" 'BEGIN { printf "%.6f", v * m }')"
mixed_regression_floor="$(awk -v v="$base_mixed" -v m="$throughput_regression_multiplier" 'BEGIN { printf "%.6f", v * m }')"
p99_regression_cap="$(awk -v v="$base_p99" -v m="$p99_regression_multiplier" 'BEGIN { printf "%.6f", v * m }')"

if lt "$latest_micro" "$micro_regression_floor"; then
  echo "perf regression failed: micro throughput $latest_micro < allowed floor $micro_regression_floor" >&2
  exit 1
fi

if lt "$latest_mixed" "$mixed_regression_floor"; then
  echo "perf regression failed: mixed throughput $latest_mixed < allowed floor $mixed_regression_floor" >&2
  exit 1
fi

if gt "$latest_p99" "$p99_regression_cap"; then
  echo "perf regression failed: p99 $latest_p99 > allowed cap $p99_regression_cap" >&2
  exit 1
fi

# FastAPI comparison gate:
# strict mode: throughput >= 5x, p99 <= 40%
# shared mode: throughput >= 4x, p99 <= 60%
fastapi_throughput_target="$(awk -v v="$fastapi_micro" -v m="$fastapi_throughput_multiplier" 'BEGIN { printf "%.6f", v * m }')"
fastapi_p99_target="$(awk -v v="$fastapi_p99" -v m="$fastapi_p99_multiplier" 'BEGIN { printf "%.6f", v * m }')"

if lt "$latest_micro" "$fastapi_throughput_target"; then
  echo "fastapi comparison failed: micro throughput $latest_micro < required target $fastapi_throughput_target" >&2
  exit 1
fi

if gt "$latest_p99" "$fastapi_p99_target"; then
  echo "fastapi comparison failed: p99 $latest_p99 > required target $fastapi_p99_target" >&2
  exit 1
fi

echo "perf gates passed (mode=$PERF_GATE_MODE): micro=$latest_micro mixed=$latest_mixed p99=$latest_p99"
