# How to Conditionally Disable OpenAPI Documentation

This recipe shows how to disable Swagger UI, ReDoc, and the OpenAPI JSON endpoint in production.

## Problem

You want to expose interactive API documentation during development but hide it in production environments.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const is_production = std.process.getEnvVarOwned(allocator, "ENV") catch null;
    defer if (is_production) |env| allocator.free(env);

    const in_prod = if (is_production) |env| std.mem.eql(u8, env, "production") else false;

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
        .docs_url = if (in_prod) null else "/docs",
        .openapi_url = if (in_prod) null else "/openapi.json",
        .redoc_url = if (in_prod) null else "/redoc",
    });
    defer app.deinit();

    // Register your routes...

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

`AppConfig` has three URL fields that control documentation endpoints:

| Field | Default | Description |
|-------|---------|-------------|
| `docs_url` | `"/docs"` | Swagger UI endpoint |
| `openapi_url` | `"/openapi.json"` | Raw OpenAPI JSON endpoint |
| `redoc_url` | `"/redoc"` | ReDoc endpoint |

Setting any of these to `null` prevents Zigmund from registering that endpoint. This is configured at app creation time -- there is no runtime toggle.

A common pattern is to read an environment variable and conditionally set the URLs based on the deployment environment.

## See Also

- [App Reference](../reference/app.md)
- [How to Configure Swagger UI](configure-swagger-ui.md)
- [How to Customize Documentation UI Assets](custom-docs-ui-assets.md)
