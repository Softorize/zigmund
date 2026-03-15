# Response Headers

Set custom HTTP headers on responses, including standard headers like `Cache-Control`, `ETag`, and `Last-Modified`, as well as application-specific custom headers.

## Overview

HTTP headers carry metadata about the response -- caching directives, API versioning, timing information, and more. Zigmund provides `response.setHeader()` for arbitrary headers and convenience methods like `response.setEtag()` and `response.setLastModified()` for common patterns.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn customHeaders(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .message = "Response includes custom headers",
    });
    try response.setHeader(allocator, "x-custom-header", "custom-value");
    try response.setHeader(allocator, "x-request-duration", "42ms");
    try response.setHeader(allocator, "x-api-version", "1.0.0");
    return response;
}

fn cacheHeaders(allocator: std.mem.Allocator) !zigmund.Response {
    var response = try zigmund.Response.json(allocator, .{
        .message = "Response includes cache-related headers",
    });
    try response.setHeader(allocator, "cache-control", "public, max-age=3600");
    try response.setEtag(allocator, "\"v1-abc123\"");
    try response.setLastModified(allocator, "Sat, 14 Mar 2026 12:00:00 GMT");
    return response;
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/custom", customHeaders, .{
        .summary = "Return response with custom headers",
    });
    try app.get("/cache", cacheHeaders, .{
        .summary = "Return response with cache-related headers",
    });
}
```

## How It Works

### 1. Setting Custom Headers

Use `response.setHeader(allocator, name, value)` to add any header to the response:

```zig
var response = try zigmund.Response.json(allocator, .{ .data = "value" });
try response.setHeader(allocator, "x-custom-header", "custom-value");
return response;
```

Note that the response must be declared as `var` (not `const`) because `setHeader` mutates the response object.

### 2. Setting Multiple Headers

Call `setHeader` multiple times to add several headers:

```zig
try response.setHeader(allocator, "x-request-id", request_id);
try response.setHeader(allocator, "x-request-duration", "42ms");
try response.setHeader(allocator, "x-api-version", "1.0.0");
```

### 3. Cache-Related Headers

Zigmund provides convenience methods for common caching headers:

```zig
// Standard Cache-Control header
try response.setHeader(allocator, "cache-control", "public, max-age=3600");

// ETag for conditional requests
try response.setEtag(allocator, "\"v1-abc123\"");

// Last-Modified timestamp
try response.setLastModified(allocator, "Sat, 14 Mar 2026 12:00:00 GMT");
```

These headers enable clients and proxies to cache responses efficiently and make conditional requests using `If-None-Match` and `If-Modified-Since`.

### 4. Header Naming Convention

HTTP headers are case-insensitive by specification. Zigmund follows the lowercase convention (e.g., `cache-control` rather than `Cache-Control`). Custom headers typically use the `x-` prefix, though this convention is no longer required by RFC 6648.

## Key Points

- Use `response.setHeader(allocator, name, value)` to add custom headers to any response.
- The response must be declared as `var` to allow mutation.
- Convenience methods `setEtag()` and `setLastModified()` handle common caching patterns.
- All header methods require an allocator because header storage is dynamically allocated.
- Headers set in handlers can also be set in middleware for cross-cutting concerns (see [Middleware](middleware.md)).

## See Also

- [Response Cookies](response-cookies.md) -- set cookies (which are also response headers).
- [Middleware](middleware.md) -- add headers to all responses via response hooks.
- [Custom Response](custom-response.md) -- different response types you can add headers to.
