#!/usr/bin/env sh
set -eu

PERF_REQUIRED_CONSECUTIVE="${PERF_REQUIRED_CONSECUTIVE:-2}"
PERF_HISTORY_WORKFLOW="${PERF_HISTORY_WORKFLOW:-perf-dedicated.yml}"
PERF_HISTORY_BRANCH="${PERF_HISTORY_BRANCH:-main}"
PERF_HISTORY_REPORT="${PERF_HISTORY_REPORT:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if [ -z "$GITHUB_REPOSITORY" ]; then
  echo "missing GITHUB_REPOSITORY (expected owner/repo)" >&2
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "missing GITHUB_TOKEN (or GH_TOKEN) for GitHub API access" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to evaluate dedicated perf run history" >&2
  exit 1
fi

case "$PERF_REQUIRED_CONSECUTIVE" in
  ''|*[!0-9]*)
    echo "PERF_REQUIRED_CONSECUTIVE must be a positive integer" >&2
    exit 1
    ;;
  *)
    if [ "$PERF_REQUIRED_CONSECUTIVE" -lt 1 ]; then
      echo "PERF_REQUIRED_CONSECUTIVE must be >= 1" >&2
      exit 1
    fi
    ;;
esac

tmp_response="$(mktemp "${TMPDIR:-/tmp}/zigmund-perf-history-XXXXXX")"
trap 'rm -f "$tmp_response"' EXIT

api_url="https://api.github.com/repos/$GITHUB_REPOSITORY/actions/workflows/$PERF_HISTORY_WORKFLOW/runs?branch=$PERF_HISTORY_BRANCH&status=completed&per_page=30"

curl -fsSL \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "$api_url" > "$tmp_response"

workflow_runs_count="$(jq '.workflow_runs | length' "$tmp_response")"
consecutive_success="$(jq '
  reduce (.workflow_runs[]?.conclusion) as $conclusion
    ({count:0,stopped:false};
      if .stopped then
        .
      else
        if $conclusion == "success" then
          {count:(.count + 1),stopped:false}
        else
          {count:.count,stopped:true}
        end
      end
    )
  | .count
' "$tmp_response")"

selected_runs_json="$(jq --argjson n "$PERF_REQUIRED_CONSECUTIVE" '[.workflow_runs[0:$n][] | {id, run_number, created_at, head_sha, html_url, conclusion}]' "$tmp_response")"

write_report() {
  verified="$1"
  reason="$2"

  if [ -z "$PERF_HISTORY_REPORT" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$PERF_HISTORY_REPORT")"
  reason_escaped="$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  cat > "$PERF_HISTORY_REPORT" <<JSON
{"generated_at":"$GENERATED_AT","repository":"$GITHUB_REPOSITORY","workflow":"$PERF_HISTORY_WORKFLOW","branch":"$PERF_HISTORY_BRANCH","required_consecutive":$PERF_REQUIRED_CONSECUTIVE,"workflow_runs_count":$workflow_runs_count,"consecutive_success":$consecutive_success,"verified":$verified,"reason":"$reason_escaped","selected_runs":$selected_runs_json}
JSON
}

if [ "$workflow_runs_count" -lt "$PERF_REQUIRED_CONSECUTIVE" ]; then
  write_report "false" "insufficient dedicated perf history"
  echo "dedicated perf history check failed: found $workflow_runs_count run(s), require at least $PERF_REQUIRED_CONSECUTIVE" >&2
  exit 1
fi

if [ "$consecutive_success" -lt "$PERF_REQUIRED_CONSECUTIVE" ]; then
  write_report "false" "insufficient consecutive successful dedicated perf runs"
  echo "dedicated perf history check failed: only $consecutive_success consecutive successful run(s), require $PERF_REQUIRED_CONSECUTIVE" >&2
  exit 1
fi

write_report "true" ""
echo "dedicated perf history verified: consecutive_success=$consecutive_success required=$PERF_REQUIRED_CONSECUTIVE"
