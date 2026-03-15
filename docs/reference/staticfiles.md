# Static Files Reference

## Overview

Zigmund serves static files from a directory with automatic content type detection, ETag-based caching, and conditional response support.

## StaticFilesOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `index_file` | `?[]const u8` | `"index.html"` | File served for directory requests |
| `cache_control` | `?[]const u8` | `"public, max-age=60"` | Cache-Control header value |
| `allow_hidden` | `bool` | `false` | Serve files starting with `.` |
| `include_in_schema` | `bool` | `false` | Include static file routes in OpenAPI |

## mountStaticFiles

```zig
pub fn mountStaticFiles(
    app: *App,
    prefix: []const u8,
    directory: []const u8,
    options: StaticFilesOptions,
) !void
```

Mounts a directory of static files at the given URL prefix.

Also available as `zigmund.mountStaticFiles`.

## StaticFilesIntegration

An object-oriented wrapper around static file serving.

### `init`

```zig
pub fn init(directory: []const u8) StaticFilesIntegration
```

Creates an integration for the given directory.

### `withOptions`

```zig
pub fn withOptions(self: StaticFilesIntegration, options: StaticFilesOptions) StaticFilesIntegration
```

Returns a copy with the given options applied.

### `mount`

```zig
pub fn mount(self: StaticFilesIntegration, app: *App, prefix: []const u8) !void
```

Mounts the static files on the app.

### `serve`

```zig
pub fn serve(self: StaticFilesIntegration, req: *Request, allocator: std.mem.Allocator) !Response
```

Serves a static file request directly (standalone mode).

## Features

- **Content type detection** -- Automatically detected from file extension (JSON, HTML, CSS, JS, images, etc.)
- **ETag caching** -- Generates ETags from file size and modification time
- **Conditional responses** -- Returns 304 Not Modified when appropriate
- **Cache-Control headers** -- Configurable cache policy
- **Security** -- Blocks path traversal (`..`), absolute paths, and hidden files by default
- **Index files** -- Serves `index.html` for directory requests

## Example

```zig
const zigmund = @import("zigmund");

pub fn main() !void {
    var app = try zigmund.App.init(allocator, .{
        .title = "My App",
        .version = "1.0",
    });
    defer app.deinit();

    // Mount static files
    try zigmund.mountStaticFiles(&app, "/static", "./public", .{
        .cache_control = "public, max-age=3600",
    });

    // Or use the integration API
    const static = zigmund.StaticFilesIntegration.init("./assets")
        .withOptions(.{ .allow_hidden = false });
    try static.mount(&app, "/assets");

    try app.serve(.{ .port = 8080 });
}
```
