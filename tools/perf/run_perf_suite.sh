#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

echo "running Zigmund performance benchmark families (ReleaseFast)"
zig build perf
