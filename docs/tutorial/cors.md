# CORS

Cross-Origin Resource Sharing (CORS) controls which browser-based clients from other domains can access your API. Zigmund provides a built-in CORS middleware that handles preflight requests and sets the appropriate response headers.

## Overview

Browsers enforce the same-origin policy, blocking JavaScript from making requests to a different domain, port, or protocol unless the server explicitly allows it. CORS headers tell the browser which origins, methods, and headers are permitted.

Zigmund's `corsMw()` function creates a middleware that automatically responds to `OPTIONS` preflight requests and attaches CORS headers to every response.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn corsProtectedEndpoint(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "This endpoint is protected by CORS middleware",
    });
}

pub fn main() !void {
    var app = try zigmund.App.init(.{ .port = 8080 });

    try app.addMiddleware(zigmund.corsMw(.{
        .allowed_origins = &.{"https://example.com"},
        .allowed_methods = &.{ "GET", "POST", "OPTIONS" },
        .allowed_headers = &.{ "Content-Type", "Authorization" },
        .allow_credentials = true,
        .max_age = 3600,
    }));

    try app.get("/data", corsProtectedEndpoint, .{});
    try app.listen();
}
```

## How It Works

1. **Registration.** `zigmund.corsMw()` takes a configuration struct and returns a `zigmund.Middleware` value. Pass it to `app.addMiddleware()` to install it.
2. **Preflight handling.** When the browser sends an `OPTIONS` request, the middleware responds immediately with the configured CORS headers and a `204 No Content` status. The route handler is never called.
3. **Normal requests.** For non-preflight requests, the middleware adds CORS headers (`Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, etc.) to the response after the handler runs.

## Configuration Options

| Option | Type | Description |
|---|---|---|
| `allowed_origins` | `[]const []const u8` | Origins permitted to access the API. Use `&.{"*"}` to allow all origins. |
| `allowed_methods` | `[]const []const u8` | HTTP methods the client may use. Typically `GET`, `POST`, `PUT`, `DELETE`, `OPTIONS`. |
| `allowed_headers` | `[]const []const u8` | Request headers the client may send. Include `Content-Type` and `Authorization` at minimum. |
| `allow_credentials` | `bool` | Whether the browser should include cookies and auth headers in cross-origin requests. Cannot be `true` if `allowed_origins` is `*`. |
| `max_age` | `u32` | How long (in seconds) the browser should cache the preflight response. `3600` (one hour) is a common value. |

## Key Points

- **Register CORS middleware early.** It should be one of the first middleware registered so that preflight responses are sent before any other middleware runs.
- **Wildcard origins.** Setting `allowed_origins` to `&.{"*"}` allows any origin. This is convenient for public APIs but incompatible with `allow_credentials = true`.
- **Credentials and cookies.** When `allow_credentials` is `true`, the browser sends cookies and authorization headers with cross-origin requests. The `Access-Control-Allow-Origin` header must be a specific origin, not `*`.
- **Preflight caching.** A higher `max_age` reduces the number of preflight `OPTIONS` requests the browser sends, improving performance for frequently called endpoints.
- **Per-route CORS is not needed.** The middleware applies to all routes. If you need different CORS policies for different route groups, use multiple sub-applications or routers with separate middleware stacks.

## See Also

- [Middleware](middleware.md) -- How middleware works in general.
- [Bigger Applications](bigger-applications.md) -- Using routers for per-group middleware configuration.
