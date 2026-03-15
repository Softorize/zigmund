# How to Configure Swagger UI

This recipe shows how to customize the Swagger UI appearance and behavior through `SwaggerUiConfig`.

## Problem

You want to change the Swagger UI page title, color theme, operation display, or authorization persistence.

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
        .docs = .{
            .title = "My Custom Docs",
            .persist_authorization = true,
            .deep_linking = true,
            .display_operation_id = true,
            .doc_expansion = .full,
            .theme = .dark,
        },
    });
    defer app.deinit();

    // Register routes...

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

The `docs` field in `AppConfig` accepts a `SwaggerUiConfig` struct with the following options:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `title` | `?[]const u8` | `null` | Custom page title. When null, uses the app title. |
| `persist_authorization` | `bool` | `false` | Remember auth credentials across page refreshes. |
| `deep_linking` | `bool` | `true` | Enable deep linking to individual operations. |
| `display_operation_id` | `bool` | `false` | Show operation IDs in the UI. |
| `doc_expansion` | `SwaggerDocExpansion` | `.list` | How operations are displayed: `.list`, `.full`, or `.none`. |
| `theme` | `DocsTheme` | `.light` | UI color theme: `.light` or `.dark`. |
| `oauth2_redirect_url` | `?[]const u8` | `null` | Custom OAuth2 redirect URL for authorization flows. |

All options have sensible defaults, so you only need to specify the fields you want to change.

## See Also

- [App Reference](../reference/app.md)
- [How to Customize Documentation UI Assets](custom-docs-ui-assets.md)
- [How to Conditionally Disable OpenAPI](conditional-openapi.md)
