#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
LATEST_FILE="$ROOT_DIR/tools/perf/latest.json"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cd "$ROOT_DIR"

echo "running Zigmund performance benchmark families (ReleaseFast)"
output="$(zig build perf 2>&1)"
printf '%s\n' "$output"

micro_line="$(printf '%s\n' "$output" | grep 'PERF_MICRO' | tail -n1 || true)"
mixed_line="$(printf '%s\n' "$output" | grep 'PERF_MIXED' | tail -n1 || true)"
tail_line="$(printf '%s\n' "$output" | grep 'PERF_TAIL' | tail -n1 || true)"

if [ -z "$micro_line" ] || [ -z "$mixed_line" ] || [ -z "$tail_line" ]; then
  echo "failed to parse perf metric lines from perf output" >&2
  exit 1
fi

extract_field() {
  line="$1"
  key="$2"
  printf '%s\n' "$line" | sed -n "s/.*$key=\\([0-9][0-9.]*\\).*/\\1/p"
}

micro_throughput="$(extract_field "$micro_line" throughput_rps)"
micro_mean_latency="$(extract_field "$micro_line" mean_latency_us)"
mixed_throughput="$(extract_field "$mixed_line" throughput_rps)"
tail_p95="$(extract_field "$tail_line" p95_us)"
tail_p99="$(extract_field "$tail_line" p99_us)"

if [ -z "$micro_throughput" ] || [ -z "$micro_mean_latency" ] || [ -z "$mixed_throughput" ] || [ -z "$tail_p95" ] || [ -z "$tail_p99" ]; then
  echo "failed to parse numeric perf metrics from benchmark output" >&2
  exit 1
fi

cat > "$LATEST_FILE" <<EOF
{"generated_at":"$GENERATED_AT","micro_throughput_rps":$micro_throughput,"micro_mean_latency_us":$micro_mean_latency,"mixed_throughput_rps":$mixed_throughput,"tail_p95_us":$tail_p95,"tail_p99_us":$tail_p99}
EOF

echo "wrote $LATEST_FILE"
