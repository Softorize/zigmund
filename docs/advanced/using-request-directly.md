# Using the Request Directly

Access the raw `*zigmund.Request` object in handlers for low-level control over request headers, path, query string, body, and HTTP method.

## Overview

While Zigmund's typed parameter injection (`Path`, `Query`, `Body`, `Depends`) covers most use cases, sometimes you need direct access to the raw request object. The `*zigmund.Request` parameter gives you access to all request properties including headers, the full path, raw query string, body bytes, and the HTTP method.

This is the Zig equivalent of using the `Request` object directly in FastAPI.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates direct access to the raw Request object.
/// The handler receives *zigmund.Request as a parameter and can inspect
/// method, path, query, headers, body, and other request properties.
fn directRequestAccess(
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user_agent = req.header("user-agent") orelse "unknown";
    const content_type = req.header("content-type") orelse "none";
    const custom_header = req.header("x-custom") orelse "not set";

    return zigmund.Response.json(allocator, .{
        .method = @tagName(req.method),
        .path = req.path,
        .query = req.query,
        .body_length = req.body.len,
        .user_agent = user_agent,
        .content_type = content_type,
        .custom_header = custom_header,
        .message = "Direct request object access",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/request-info", directRequestAccess, .{
        .summary = "Direct request object access for headers, path, query, and body",
    });

    // Also register POST to demonstrate body access
    try app.post("/request-info", directRequestAccess, .{
        .summary = "Direct request object access (POST with body)",
    });
}
```

## How It Works

### 1. Request Properties

The `*zigmund.Request` object exposes the following properties:

| Property     | Type           | Description                                  |
|--------------|----------------|----------------------------------------------|
| `method`     | enum           | HTTP method (`.GET`, `.POST`, `.PUT`, etc.). |
| `path`       | `[]const u8`   | The request path (e.g., `/items/42`).        |
| `query`      | `[]const u8`   | The raw query string (e.g., `skip=0&limit=10`). |
| `body`       | `[]const u8`   | The raw request body bytes.                  |

### 2. Reading Headers

Use `req.header(name)` to read a header value. It returns an optional (`?[]const u8`):

```zig
const user_agent = req.header("user-agent") orelse "unknown";
const auth = req.header("authorization") orelse return error.Unauthorized;
```

Header names are case-insensitive.

### 3. Getting the HTTP Method

The `method` field is an enum. Use `@tagName()` to convert it to a string:

```zig
const method_str = @tagName(req.method);  // "GET", "POST", etc.
```

### 4. Accessing the Body

The `body` field contains the raw request body as a byte slice. For GET requests, this is typically empty. For POST/PUT/PATCH requests, it contains the submitted data:

```zig
const body_length = req.body.len;
```

For JSON parsing, you would typically use `zigmund.Body()` typed parameter injection instead of parsing `req.body` manually. However, direct body access is useful for custom content types or binary payloads.

### 5. Combining with Typed Parameters

You can use `*zigmund.Request` alongside typed parameter injection in the same handler:

```zig
fn myHandler(
    req: *zigmund.Request,
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const auth = req.header("authorization") orelse return error.Unauthorized;
    const id = item_id.value.?;
    // ...
}
```

## Key Points

- `*zigmund.Request` provides raw access to all request properties.
- Use `req.header(name)` for case-insensitive header lookup, returning an optional.
- The same handler function can be registered for multiple HTTP methods.
- Direct request access can be combined with typed parameter injection in the same handler.
- Prefer typed parameters (`Path`, `Query`, `Body`) when possible -- they provide compile-time type safety and automatic OpenAPI documentation.

## See Also

- [Response Directly](response-directly.md) -- return raw responses for full control over output.
- [Middleware](middleware.md) -- access the request in middleware hooks.
- [Advanced Dependencies](advanced-dependencies.md) -- dependency providers can also receive `*zigmund.Request`.
