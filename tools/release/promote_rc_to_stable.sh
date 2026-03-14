#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  echo "usage: $0 <rc-tag> [stable-tag] [--execute]" >&2
  echo "example: $0 rc-1.0.0 v1.0.0 --execute" >&2
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

execute="0"
rc_tag=""
stable_tag=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --execute)
      execute="1"
      shift
      ;;
    --dry-run)
      execute="0"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -z "$rc_tag" ]; then
        rc_tag="$1"
      elif [ -z "$stable_tag" ]; then
        stable_tag="$1"
      else
        echo "unexpected argument: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

case "$rc_tag" in
  rc-*)
    ;;
  *)
    echo "rc tag must start with 'rc-': $rc_tag" >&2
    exit 1
    ;;
esac

if [ -z "$stable_tag" ]; then
  base_version="${rc_tag#rc-}"
  base_version="${base_version%%-rc*}"
  case "$base_version" in
    v*) stable_tag="$base_version" ;;
    *) stable_tag="v$base_version" ;;
  esac
fi

if ! git rev-parse -q --verify "refs/tags/$rc_tag" >/dev/null; then
  echo "missing rc tag locally: $rc_tag" >&2
  echo "fetch tags first: git fetch --tags" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$stable_tag" >/dev/null; then
  echo "stable tag already exists locally: $stable_tag" >&2
  exit 1
fi

release_evidence="${RELEASE_EVIDENCE_PATH:-dist/release/release-evidence.json}"
require_rc_evidence="${REQUIRE_RC_EVIDENCE:-0}"
if [ -f "$release_evidence" ] && ! grep -q '"channel":"rc"' "$release_evidence"; then
  if [ "$require_rc_evidence" = "1" ]; then
    echo "release evidence does not indicate rc channel: $release_evidence" >&2
    exit 1
  fi
  echo "warning: release evidence is present but not rc-scoped: $release_evidence" >&2
fi

rc_commit="$(git rev-list -n 1 "$rc_tag")"
message="Release $stable_tag (promoted from $rc_tag)"

if [ "$execute" = "1" ]; then
  git tag -a "$stable_tag" "$rc_commit" -m "$message"
  git push origin "$stable_tag"
  echo "promoted $rc_tag -> $stable_tag"
else
  echo "dry-run: promotion plan"
  echo "  rc tag: $rc_tag"
  echo "  stable tag: $stable_tag"
  echo "  commit: $rc_commit"
  echo "  git tag -a $stable_tag $rc_commit -m \"$message\""
  echo "  git push origin $stable_tag"
fi
