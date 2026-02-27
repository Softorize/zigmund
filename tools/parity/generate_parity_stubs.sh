#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
URLS_FILE="$ROOT_DIR/tools/parity/fastapi_urls.txt"

if [ ! -f "$URLS_FILE" ]; then
  sh "$ROOT_DIR/tools/parity/fetch_fastapi_sitemap.sh"
fi

created=0

while IFS= read -r doc_path; do
  category="$(printf '%s' "$doc_path" | cut -d'/' -f1)"
  remainder="$(printf '%s' "$doc_path" | cut -d'/' -f2- | sed 's#/$##')"

  if [ -z "$remainder" ]; then
    slug="index"
  else
    slug="$(printf '%s' "$remainder" | sed 's#/#__#g')"
  fi

  out_dir="$ROOT_DIR/examples/parity/$category"
  out_file="$out_dir/$slug.zig"

  if [ -f "$out_file" ]; then
    continue
  fi

  mkdir -p "$out_dir"

  cat > "$out_file" <<STUB
const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: $doc_path

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "$doc_path",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/$category/$slug", placeholder, .{
        .summary = "Parity stub for $doc_path",
        .tags = &.{"parity", "$category"},
    });
}
STUB

  created=$((created + 1))
done < "$URLS_FILE"

printf 'Created %s parity stub file(s).\n' "$created"
