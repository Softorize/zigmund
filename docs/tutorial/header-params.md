# Header Parameters

Read typed values from HTTP request headers using the `Header()` parameter marker.

## Overview

HTTP headers carry metadata about the request: content types, authentication tokens, user agents, caching directives, and custom application headers. In Zigmund you extract header values with the `Header()` parameter marker, which works the same way as `Path()` and `Query()` -- declare it in the handler signature, and the framework injects the parsed value.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readItems(
    // Required header -- Zigmund returns 422 if missing.
    user_agent: zigmund.Header([]const u8, .{ .alias = "user-agent" }),
    // Optional header -- the inner type is ?[]const u8.
    accept: zigmund.Header(?[]const u8, .{ .alias = "accept" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .user_agent = user_agent.value.?,
        .accept = accept.value.? orelse "not provided",
    });
}

// Registration:
// app.get("/items", readItems, .{})
```

### Request example

```bash
curl http://127.0.0.1:8000/items \
  -H "Accept: application/json"
```

Response:

```json
{
  "user_agent": "curl/8.1.2",
  "accept": "application/json"
}
```

## How It Works

### 1. Declare header parameters with Header()

Add `zigmund.Header(T, options)` parameters to your handler:

```zig
fn readItems(
    user_agent: zigmund.Header([]const u8, .{ .alias = "user-agent" }),
    accept: zigmund.Header(?[]const u8, .{ .alias = "accept" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
```

### 2. The .alias option

The `.alias` specifies the actual HTTP header name. This is especially important for headers that contain hyphens (e.g., `user-agent`, `content-type`, `x-request-id`), because Zig identifiers cannot contain hyphens:

```zig
// The Zig parameter name is "user_agent", but the HTTP header is "user-agent".
user_agent: zigmund.Header([]const u8, .{ .alias = "user-agent" }),
```

### 3. Required vs. optional headers

The mechanism for making a header optional is different from `Query()`. Instead of a `.required` option, you make the type itself optional by wrapping it in `?`:

| Declaration                                                      | Behavior                                     |
|------------------------------------------------------------------|----------------------------------------------|
| `Header([]const u8, .{ .alias = "user-agent" })`                | Required. Missing = 422 error.               |
| `Header(?[]const u8, .{ .alias = "accept" })`                   | Optional. Missing = `null`.                  |

For optional headers, you unwrap with a double pattern: `.value.?` gives you the `?[]const u8`, then `orelse` provides the fallback:

```zig
const accept_value = accept.value.? orelse "not provided";
```

### 4. Underscore conversion

By default, `HeaderOptions` has `convert_underscores: true`. This means that if your Zig parameter name uses underscores, the framework can automatically convert them to hyphens when looking up the header. However, using `.alias` explicitly is the clearest approach and is recommended.

### 5. HeaderOptions reference

| Field                  | Type                 | Default | Description                                        |
|------------------------|----------------------|---------|----------------------------------------------------|
| `alias`                | `?[]const u8`        | `null`  | The HTTP header name to read.                      |
| `convert_underscores`  | `bool`               | `true`  | Auto-convert `_` to `-` in the parameter name.     |
| `description`          | `?[]const u8`        | `null`  | Description for OpenAPI docs.                      |
| `gt`, `ge`, `lt`, `le` | `?f64`              | `null`  | Numeric validation constraints.                    |
| `min_length`           | `?usize`             | `null`  | Minimum string length.                             |
| `max_length`           | `?usize`             | `null`  | Maximum string length.                             |
| `pattern`              | `?[]const u8`        | `null`  | Regex pattern for validation.                      |
| `enum_values`          | `[]const []const u8` | `&.{}`  | Restrict to a fixed set of string values.          |

### 6. Common use cases

**Custom API key header:**

```zig
fn securedEndpoint(
    api_key: zigmund.Header([]const u8, .{ .alias = "x-api-key" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // api_key.value.? contains the key value.
}
```

**Conditional requests with If-None-Match:**

```zig
fn cachedResource(
    etag: zigmund.Header(?[]const u8, .{ .alias = "if-none-match" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (etag.value.?) |tag| {
        if (std.mem.eql(u8, tag, "\"abc123\"")) {
            return zigmund.Response.text("").withStatus(.not_modified);
        }
    }
    // Return full response...
}
```

## Key Points

- `Header()` extracts values from HTTP request headers, with automatic type conversion.
- Use `.alias` to map Zig parameter names (which use underscores) to HTTP header names (which use hyphens).
- Make a header optional by declaring the type as `?[]const u8` (or any optional type) rather than setting a `.required` flag.
- Header parameters appear in the auto-generated OpenAPI documentation with their types and descriptions.
- The `convert_underscores` option is `true` by default, but using an explicit `.alias` is clearer and recommended.

## See Also

- [Cookie Parameters](cookie-params.md) -- reading values from cookies.
- [Query Parameters](query-parameters.md) -- reading values from the query string.
- [Path Parameters](path-parameters.md) -- reading values from the URL path.
