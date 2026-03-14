#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
EVIDENCE_FILE="$DIST_DIR/release-evidence.json"
PARITY_SUMMARY="$ROOT_DIR/tools/parity/parity-summary.json"
API_PARITY_SUMMARY="$ROOT_DIR/tools/parity/api-parity-summary.json"
PERF_LATEST="$ROOT_DIR/tools/perf/latest.json"
PERF_GATE_REPORT="$DIST_DIR/perf-gate-report.json"
PERF_HISTORY_REPORT="$DIST_DIR/perf-history.json"
RUNTIME_SOAK_HISTORY_REPORT="$DIST_DIR/runtime-soak-history.json"
RELEASE_METADATA="$DIST_DIR/release-metadata.json"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-dev}"
RELEASE_REF="${RELEASE_REF:-}"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
COMMIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

mkdir -p "$DIST_DIR"

extract_number() {
  file="$1"
  key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9.]*\\).*/\\1/p" "$file" | head -n1
}

extract_string() {
  file="$1"
  key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n1
}

extract_boolean() {
  file="$1"
  key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\(true\\|false\\).*/\\1/p" "$file" | head -n1
}

for required in "$PARITY_SUMMARY" "$API_PARITY_SUMMARY" "$PERF_LATEST" "$RELEASE_METADATA"; do
  if [ ! -f "$required" ]; then
    echo "missing required release evidence input: $required" >&2
    exit 1
  fi
done

parity_total="$(extract_number "$PARITY_SUMMARY" total)"
parity_implemented="$(extract_number "$PARITY_SUMMARY" implemented)"
parity_stub="$(extract_number "$PARITY_SUMMARY" stub)"
parity_missing="$(extract_number "$PARITY_SUMMARY" missing)"

api_total="$(extract_number "$API_PARITY_SUMMARY" total)"
api_implemented="$(extract_number "$API_PARITY_SUMMARY" implemented)"
api_missing="$(extract_number "$API_PARITY_SUMMARY" missing)"

perf_micro="$(extract_number "$PERF_LATEST" micro_throughput_rps)"
perf_mixed="$(extract_number "$PERF_LATEST" mixed_throughput_rps)"
perf_p99="$(extract_number "$PERF_LATEST" tail_p99_us)"

for value in \
  "$parity_total" "$parity_implemented" "$parity_stub" "$parity_missing" \
  "$api_total" "$api_implemented" "$api_missing" \
  "$perf_micro" "$perf_mixed" "$perf_p99"; do
  if [ -z "$value" ]; then
    echo "failed to parse required release evidence metrics" >&2
    exit 1
  fi
done

perf_gate_status="null"
perf_gate_state="unknown"
perf_gate_reason=""
if [ -f "$PERF_GATE_REPORT" ]; then
  gate_status_value="$(extract_string "$PERF_GATE_REPORT" status)"
  gate_reason_value="$(extract_string "$PERF_GATE_REPORT" reason)"
  if [ -n "$gate_status_value" ]; then
    perf_gate_status="\"$gate_status_value\""
    perf_gate_state="$gate_status_value"
  fi
  perf_gate_reason="$gate_reason_value"
fi

dedicated_verified="null"
dedicated_consecutive="null"
dedicated_required="null"
if [ -f "$PERF_HISTORY_REPORT" ]; then
  verified_value="$(extract_boolean "$PERF_HISTORY_REPORT" verified)"
  consecutive_value="$(extract_number "$PERF_HISTORY_REPORT" consecutive_success)"
  required_value="$(extract_number "$PERF_HISTORY_REPORT" required_consecutive)"
  if [ -n "$verified_value" ]; then
    dedicated_verified="$verified_value"
  fi
  if [ -n "$consecutive_value" ]; then
    dedicated_consecutive="$consecutive_value"
  fi
  if [ -n "$required_value" ]; then
    dedicated_required="$required_value"
  fi
fi

runtime_soak_verified="null"
runtime_soak_consecutive="null"
runtime_soak_required="null"
if [ -f "$RUNTIME_SOAK_HISTORY_REPORT" ]; then
  runtime_verified_value="$(extract_boolean "$RUNTIME_SOAK_HISTORY_REPORT" verified)"
  runtime_consecutive_value="$(extract_number "$RUNTIME_SOAK_HISTORY_REPORT" consecutive_success)"
  runtime_required_value="$(extract_number "$RUNTIME_SOAK_HISTORY_REPORT" required_consecutive)"
  if [ -n "$runtime_verified_value" ]; then
    runtime_soak_verified="$runtime_verified_value"
  fi
  if [ -n "$runtime_consecutive_value" ]; then
    runtime_soak_consecutive="$runtime_consecutive_value"
  fi
  if [ -n "$runtime_required_value" ]; then
    runtime_soak_required="$runtime_required_value"
  fi
fi

dedicated_perf_gate_state="not_required"
if [ "$dedicated_verified" = "true" ]; then
  dedicated_perf_gate_state="passed"
elif [ "$dedicated_verified" = "false" ]; then
  dedicated_perf_gate_state="failed"
fi

runtime_soak_gate_state="not_required"
if [ "$runtime_soak_verified" = "true" ]; then
  runtime_soak_gate_state="passed"
elif [ "$runtime_soak_verified" = "false" ]; then
  runtime_soak_gate_state="failed"
fi

if [ -z "$RELEASE_REF" ]; then
  RELEASE_REF="$(extract_string "$RELEASE_METADATA" ref)"
fi

perf_gate_reason_escaped="$(printf '%s' "$perf_gate_reason" | sed 's/\\/\\\\/g; s/"/\\"/g')"

cat > "$EVIDENCE_FILE" <<JSON
{"generated_at":"$GENERATED_AT","channel":"$RELEASE_CHANNEL","ref":"$RELEASE_REF","commit":"$COMMIT_SHA","gates":{"tests":"passed","parity":"passed","perf":"$perf_gate_state","governance":"passed","dedicated_perf_history":"$dedicated_perf_gate_state","runtime_soak":"$runtime_soak_gate_state"},"parity":{"total":$parity_total,"implemented":$parity_implemented,"stub":$parity_stub,"missing":$parity_missing},"api_parity":{"total":$api_total,"implemented":$api_implemented,"missing":$api_missing},"perf":{"latest":{"micro_throughput_rps":$perf_micro,"mixed_throughput_rps":$perf_mixed,"tail_p99_us":$perf_p99},"gate_status":$perf_gate_status,"gate_reason":"$perf_gate_reason_escaped"},"dedicated_perf_history":{"verified":$dedicated_verified,"consecutive_success":$dedicated_consecutive,"required_consecutive":$dedicated_required},"runtime_soak_history":{"verified":$runtime_soak_verified,"consecutive_success":$runtime_soak_consecutive,"required_consecutive":$runtime_soak_required},"inputs":{"parity_summary":"tools/parity/parity-summary.json","api_parity_summary":"tools/parity/api-parity-summary.json","perf_latest":"tools/perf/latest.json","perf_gate_report":"dist/release/perf-gate-report.json","perf_history_report":"dist/release/perf-history.json","runtime_soak_history_report":"dist/release/runtime-soak-history.json","release_metadata":"dist/release/release-metadata.json"}}
JSON

shasum -a 256 "$EVIDENCE_FILE" > "$EVIDENCE_FILE.sha256"

echo "release evidence written to $EVIDENCE_FILE"
