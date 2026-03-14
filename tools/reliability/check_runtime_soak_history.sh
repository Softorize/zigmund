#!/usr/bin/env sh
set -eu

RUNTIME_SOAK_REQUIRED_CONSECUTIVE="${RUNTIME_SOAK_REQUIRED_CONSECUTIVE:-1}"
RUNTIME_SOAK_WORKFLOW="${RUNTIME_SOAK_WORKFLOW:-runtime-soak.yml}"
RUNTIME_SOAK_BRANCH="${RUNTIME_SOAK_BRANCH:-main}"
RUNTIME_SOAK_HISTORY_REPORT="${RUNTIME_SOAK_HISTORY_REPORT:-}"
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
  echo "jq is required to evaluate runtime soak history" >&2
  exit 1
fi

case "$RUNTIME_SOAK_REQUIRED_CONSECUTIVE" in
  ''|*[!0-9]*)
    echo "RUNTIME_SOAK_REQUIRED_CONSECUTIVE must be a positive integer" >&2
    exit 1
    ;;
  *)
    if [ "$RUNTIME_SOAK_REQUIRED_CONSECUTIVE" -lt 1 ]; then
      echo "RUNTIME_SOAK_REQUIRED_CONSECUTIVE must be >= 1" >&2
      exit 1
    fi
    ;;
esac

tmp_response="$(mktemp "${TMPDIR:-/tmp}/zigmund-runtime-soak-history-XXXXXX")"
trap 'rm -f "$tmp_response"' EXIT

api_url="https://api.github.com/repos/$GITHUB_REPOSITORY/actions/workflows/$RUNTIME_SOAK_WORKFLOW/runs?branch=$RUNTIME_SOAK_BRANCH&status=completed&per_page=30"

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

selected_runs_json="$(jq --argjson n "$RUNTIME_SOAK_REQUIRED_CONSECUTIVE" '[.workflow_runs[0:$n][] | {id, run_number, created_at, head_sha, html_url, conclusion}]' "$tmp_response")"

write_report() {
  verified="$1"
  reason="$2"

  if [ -z "$RUNTIME_SOAK_HISTORY_REPORT" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$RUNTIME_SOAK_HISTORY_REPORT")"
  reason_escaped="$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  cat > "$RUNTIME_SOAK_HISTORY_REPORT" <<JSON
{"generated_at":"$GENERATED_AT","repository":"$GITHUB_REPOSITORY","workflow":"$RUNTIME_SOAK_WORKFLOW","branch":"$RUNTIME_SOAK_BRANCH","required_consecutive":$RUNTIME_SOAK_REQUIRED_CONSECUTIVE,"workflow_runs_count":$workflow_runs_count,"consecutive_success":$consecutive_success,"verified":$verified,"reason":"$reason_escaped","selected_runs":$selected_runs_json}
JSON
}

if [ "$workflow_runs_count" -lt "$RUNTIME_SOAK_REQUIRED_CONSECUTIVE" ]; then
  write_report "false" "insufficient runtime soak history"
  echo "runtime soak history check failed: found $workflow_runs_count run(s), require at least $RUNTIME_SOAK_REQUIRED_CONSECUTIVE" >&2
  exit 1
fi

if [ "$consecutive_success" -lt "$RUNTIME_SOAK_REQUIRED_CONSECUTIVE" ]; then
  write_report "false" "insufficient consecutive successful runtime soak runs"
  echo "runtime soak history check failed: only $consecutive_success consecutive successful run(s), require $RUNTIME_SOAK_REQUIRED_CONSECUTIVE" >&2
  exit 1
fi

write_report "true" ""
echo "runtime soak history verified: consecutive_success=$consecutive_success required=$RUNTIME_SOAK_REQUIRED_CONSECUTIVE"
