# Query Parameters

Read typed values from the URL query string using the `Query()` parameter marker.

## Overview

Query parameters are the key-value pairs that appear after the `?` in a URL, such as `/items?skip=0&limit=10`. They are commonly used for pagination, filtering, and sorting. In Zigmund you declare query parameters in the handler signature with the `Query()` marker. Each parameter can be required or optional, and the framework handles parsing, type conversion, and default-value logic for you.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn listItems(
    // Both parameters are optional (required = false).
    // When the caller omits them, .value will be null.
    skip: zigmund.Query(u32, .{ .alias = "skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // Use `orelse` to supply defaults when the query parameter is absent.
    const resolved_skip = skip.value orelse 0;
    const resolved_limit = limit.value orelse 10;
    return zigmund.Response.json(allocator, .{
        .skip = resolved_skip,
        .limit = resolved_limit,
    });
}

// Registration:
// app.get("/items", listItems, .{})
```

### Request examples

| URL                              | skip | limit |
|----------------------------------|------|-------|
| `/items`                         | 0    | 10    |
| `/items?skip=20`                 | 20   | 10    |
| `/items?skip=5&limit=50`         | 5    | 50    |

## How It Works

### 1. Declare query parameters with Query()

Add a `zigmund.Query(T, options)` parameter to your handler. Like `Path()`, it is a comptime generic that produces a typed marker struct:

```zig
fn listItems(
    skip: zigmund.Query(u32, .{ .alias = "skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
```

### 2. The .alias option

`.alias` specifies the query string key that maps to this parameter. It must match the key the client sends in the URL:

```
GET /items?skip=20
              ^^^^ matches .alias = "skip"
```

### 3. Required vs. optional

The `.required` field controls whether the parameter must be present:

| `.required` | Behavior when missing                          |
|-------------|-------------------------------------------------|
| `true`      | Zigmund returns a 422 validation error.         |
| `false`     | `.value` is `null`; the handler decides the default. |

The default for `.required` is `true`. Set it to `false` for optional parameters.

### 4. Using orelse for defaults

When a query parameter is optional, `.value` is `?T` (an optional). Use Zig's `orelse` keyword to provide a fallback:

```zig
const resolved_skip = skip.value orelse 0;
```

This is the idiomatic Zig equivalent of Python's `skip: int = 0` default parameter.

### 5. QueryOptions reference

| Field              | Type                      | Default | Description                                        |
|--------------------|---------------------------|---------|----------------------------------------------------|
| `alias`            | `?[]const u8`             | `null`  | Query string key name.                             |
| `description`      | `?[]const u8`             | `null`  | Description for OpenAPI docs.                      |
| `required`         | `bool`                    | `true`  | Whether the parameter must be present.             |
| `deprecated`       | `bool`                    | `false` | Mark as deprecated in OpenAPI docs.                |
| `gt`, `ge`, `lt`, `le` | `?f64`               | `null`  | Numeric validation constraints.                    |
| `min_length`       | `?usize`                  | `null`  | Minimum string length.                             |
| `max_length`       | `?usize`                  | `null`  | Maximum string length.                             |
| `pattern`          | `?[]const u8`             | `null`  | Regex pattern for validation.                      |
| `enum_values`      | `[]const []const u8`      | `&.{}`  | Restrict to a fixed set of string values.          |

### 6. Combining with other parameter types

Query parameters work alongside path parameters and request bodies in the same handler:

```zig
fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    verbose: zigmund.Query(bool, .{ .alias = "verbose", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // item_id comes from the URL path, verbose comes from the query string.
    const detail = verbose.value orelse false;
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .verbose = detail,
    });
}
```

## Key Points

- Query parameters are declared in the handler signature with `Query(T, options)`, not extracted manually from the request.
- Set `.required = false` to make a parameter optional; its `.value` will be `null` when omitted.
- Use `orelse` to supply default values for optional parameters -- this is the Zig equivalent of Python default arguments.
- Zigmund parses and validates query string values at the framework level. Type mismatches produce a 422 error automatically.
- All query parameters appear in the auto-generated OpenAPI documentation with their types and required/optional status.

## See Also

- [Path Parameters](path-parameters.md) -- capture values from the URL path.
- [Request Body](request-body.md) -- accept structured JSON payloads.
- [Header Parameters](header-params.md) -- read values from HTTP headers.
