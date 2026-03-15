# How to Customize Authentication Error Status Codes

This recipe shows how to return a custom HTTP status code (such as 403 Forbidden) when authentication fails, instead of the default 401 Unauthorized.

## Problem

You want failed authentication attempts to return 403 Forbidden (or another custom status) instead of the default 401 Unauthorized response.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn customUnauthorizedHandler(
    _: *const zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .detail = "Access denied: invalid or missing credentials",
    })).withStatus(.forbidden);
}

const bearer_scheme = zigmund.HTTPBearer{};

fn protectedRoute(
    token: zigmund.Security(bearer_scheme, &.{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = token.value.?,
        .message = "Authenticated successfully",
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    // Set custom handler that returns 403 instead of 401
    app.setUnauthorizedHandler(customUnauthorizedHandler);

    try app.addSecurityScheme("bearerAuth", .{
        .http = .{ .scheme = "bearer", .bearer_format = "JWT" },
    });

    try app.get("/protected", protectedRoute, .{
        .summary = "Protected endpoint",
    });

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

By default, when a `Security` parameter fails to resolve (the request lacks valid credentials), Zigmund returns a 401 Unauthorized response. You can override this behavior:

1. **`app.setUnauthorizedHandler(handler)`** -- Sets a custom handler called when authentication fails (Unauthorized error). The handler receives the request and allocator, and must return a `Response`.

2. **`app.setInsufficientScopeHandler(handler)`** -- Sets a custom handler called when the user is authenticated but lacks the required scopes (InsufficientScope error).

The custom handler can return any status code, custom headers, or a detailed error body. This is useful for APIs that prefer 403 Forbidden over 401 Unauthorized, or that need to include additional error details.

## See Also

- [Security Reference](../reference/security.md)
- [App Reference](../reference/app.md)
- [Exceptions Reference](../reference/exceptions.md)
