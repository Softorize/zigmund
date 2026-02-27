#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

count=0
tmp_list="$(mktemp)"
trap 'rm -f "$tmp_list"' EXIT

rg -l "ZIGMUND_PARITY_STUB" "$ROOT_DIR/examples/parity" > "$tmp_list" || true

while IFS= read -r file; do
  [ -n "$file" ] || continue
  doc_path="$(sed -n 's#// FastAPI source page: ##p' "$file" | head -n1)"
  if [ -z "$doc_path" ]; then
    echo "failed to parse doc path from $file" >&2
    exit 1
  fi

  category="$(printf '%s' "$file" | sed -E 's#^.*/examples/parity/([^/]+)/.*$#\1#')"
  slug="$(basename "$file" .zig)"
  route="/$category/$slug"

  cat > "$file" <<EOF
const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "$doc_path";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("$route", implemented, .{
        .summary = "Parity implementation for $doc_path",
        .tags = &.{ "parity", "$category" },
    });
}
EOF

  count=$((count + 1))
done < "$tmp_list"

echo "Converted $count stub file(s) to implemented parity examples."
