# Path Parameters

Extract typed values from URL path segments using the `Path()` parameter marker.

## Overview

Many APIs include dynamic identifiers in the URL itself -- for example, `/items/42` or `/users/alice`. In Zigmund you declare these dynamic segments in the route path with curly braces (`{item_id}`) and receive the parsed value as a handler parameter. The framework validates and converts the raw string into the target Zig type before your handler is called.

This is the Zigmund equivalent of FastAPI's path parameters, with the added benefit that the type conversion is enforced at compile time.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readItem(
    // Declare a path parameter of type u32 whose URL segment is named "item_id".
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
    });
}

// Registration -- the {item_id} segment in the path matches the .alias above.
// app.get("/items/{item_id}", readItem, .{})
```

## How It Works

### 1. Define the route path

When you register the route, place the parameter name inside curly braces:

```zig
try app.get("/items/{item_id}", readItem, .{});
```

Zigmund's router treats `{item_id}` as a dynamic segment. Any non-empty string in that position will match. Multiple path parameters are supported:

```zig
try app.get("/users/{user_id}/orders/{order_id}", readUserOrder, .{});
```

### 2. Declare the handler parameter with Path()

In the handler signature, use `zigmund.Path(T, options)` to declare what type the segment should be parsed into:

```zig
fn readItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
```

`Path()` is a comptime generic that produces a struct type carrying metadata about the parameter. It accepts two arguments:

| Argument  | Description                                                        |
|-----------|--------------------------------------------------------------------|
| `T`       | The target Zig type. Common choices: `u32`, `i64`, `[]const u8`.   |
| `options` | A `PathOptions` struct. `.alias` is the most commonly used field.  |

### 3. The .alias option

The `.alias` field tells Zigmund which `{segment}` in the URL path this parameter corresponds to. It must match the name used in the route path string exactly.

```zig
// Route:   "/items/{item_id}"
// Alias:   .{ .alias = "item_id" }
//                       ^^^^^^^^^ must match
```

### 4. Access the value with .value.?

The parsed value lives in the `.value` field, which is an optional (`?T`). For path parameters the value is always present when the handler is called (the request would not have matched the route otherwise), so you unwrap it with `.?`:

```zig
const id = item_id.value.?; // u32
```

### 5. PathOptions reference

| Field              | Type                      | Default | Description                                        |
|--------------------|---------------------------|---------|----------------------------------------------------|
| `alias`            | `?[]const u8`             | `null`  | Name of the URL segment to bind to.                |
| `description`      | `?[]const u8`             | `null`  | Description shown in OpenAPI docs.                 |
| `gt`, `ge`, `lt`, `le` | `?f64`               | `null`  | Numeric validation constraints.                    |
| `min_length`       | `?usize`                  | `null`  | Minimum string length.                             |
| `max_length`       | `?usize`                  | `null`  | Maximum string length.                             |
| `pattern`          | `?[]const u8`             | `null`  | Regex pattern for validation.                      |
| `enum_values`      | `[]const []const u8`      | `&.{}`  | Restrict to a fixed set of string values.          |

## Key Points

- Path parameters use curly-brace syntax in the route string: `"/items/{item_id}"`.
- The `Path()` marker in the handler signature declares the expected type and maps to a URL segment via `.alias`.
- Path parameters are always required -- if the segment is missing, the route simply does not match.
- Zigmund automatically parses the raw string into the target type (e.g., `u32`). If parsing fails, the client receives a 422 validation error.
- The handler uses an alternative signature (no `req` pointer). When you use parameter markers like `Path()`, `Query()`, or `Body()`, Zigmund injects them directly -- you do not need `*zigmund.Request` as the first argument.

## See Also

- [First Steps](first-steps.md) -- the basic handler signature with `*zigmund.Request`.
- [Query Parameters](query-parameters.md) -- optional and required query string values.
- [Request Body](request-body.md) -- accepting structured JSON payloads.
