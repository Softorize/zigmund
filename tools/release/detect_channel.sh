#!/usr/bin/env sh
set -eu

input_channel="${1:-}"
ref_name="${GITHUB_REF_NAME:-}"

if [ -n "$input_channel" ]; then
  channel="$input_channel"
elif [ -n "$ref_name" ]; then
  case "$ref_name" in
    nightly-*)
      channel="nightly"
      ;;
    alpha-*)
      channel="alpha"
      ;;
    beta-*)
      channel="beta"
      ;;
    rc-*)
      channel="rc"
      ;;
    v*)
      channel="stable"
      ;;
    *)
      channel="nightly"
      ;;
  esac
else
  channel="nightly"
fi

case "$channel" in
  nightly|alpha|beta|rc|stable)
    ;;
  *)
    echo "invalid release channel: $channel" >&2
    exit 1
    ;;
esac

printf '%s\n' "$channel"
