# How to Customize Documentation UI Assets

This recipe shows how to customize the documentation UI endpoints and configure both Swagger UI and ReDoc.

## Problem

You want to change the URL paths for documentation endpoints or customize the ReDoc UI configuration.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
        .docs_url = "/swagger",       // Custom Swagger UI path
        .redoc_url = "/reference",     // Custom ReDoc path
        .docs = .{
            .title = "My API Docs",
            .theme = .dark,
        },
        .redoc = .{
            .title = "My API Reference",
            .hide_download_button = true,
            .theme = .dark,
        },
    });
    defer app.deinit();

    // Register routes...

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

Zigmund embeds Swagger UI and ReDoc assets at compile time -- no external CDN is required. You can customize the documentation through two mechanisms:

**URL configuration** in `AppConfig`:

| Field | Default | Description |
|-------|---------|-------------|
| `docs_url` | `"/docs"` | Path for Swagger UI |
| `redoc_url` | `"/redoc"` | Path for ReDoc |
| `openapi_url` | `"/openapi.json"` | Path for raw OpenAPI JSON |

**ReDoc UI configuration** via `AppConfig.redoc` (`RedocUiConfig`):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `title` | `?[]const u8` | `null` | Custom page title |
| `hide_download_button` | `bool` | `false` | Hide the schema download button |
| `disable_search` | `bool` | `false` | Disable search functionality |
| `theme` | `DocsTheme` | `.light` | Color theme: `.light` or `.dark` |

Both documentation UIs are available by default at `/docs` and `/redoc`. Set any URL to `null` to disable that endpoint.

## See Also

- [App Reference](../reference/app.md)
- [How to Configure Swagger UI](configure-swagger-ui.md)
- [How to Conditionally Disable OpenAPI](conditional-openapi.md)
