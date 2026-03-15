# How to Extend OpenAPI with Custom Fields

This recipe shows how to add custom `x-` extension fields to the OpenAPI specification at both the app level and route level.

## Problem

You want to add vendor-specific metadata to your OpenAPI specification, such as rate limit information, team ownership, or stability markers.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn myHandler(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .status = "ok" });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // App-level extensions appear at the top level of the OpenAPI spec
    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
        .openapi_extensions = &.{
            .{ .key = "x-api-team", .value_json = "\"platform\"" },
            .{ .key = "x-stability", .value_json = "\"stable\"" },
        },
    });
    defer app.deinit();

    // Route-level extensions appear on individual operations
    try app.get("/status", myHandler, .{
        .summary = "Service status",
        .openapi_extensions = &.{
            .{ .key = "x-rate-limit", .value_json = "\"100 req/min\"" },
            .{ .key = "x-internal", .value_json = "false" },
        },
    });

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

OpenAPI extensions use the `x-` prefix convention for custom metadata. Zigmund supports them at two levels:

**App-level extensions** -- Set via `AppConfig.openapi_extensions`. These appear at the root of the generated OpenAPI document.

**Route-level extensions** -- Set via `RouteOptions.openapi_extensions`. These appear on individual path operations.

Each extension is an `OpenApiExtension` struct with two fields:

| Field | Type | Description |
|-------|------|-------------|
| `key` | `[]const u8` | The extension key (must start with `x-`) |
| `value_json` | `[]const u8` | The JSON-encoded value (strings must include quotes) |

The `value_json` field accepts raw JSON, so strings must be wrapped in quotes (`"\"value\""`) while numbers and booleans are written directly (`"false"`, `"100"`).

## See Also

- [OpenAPI Reference](../reference/openapi.md)
- [App Reference](../reference/app.md)
