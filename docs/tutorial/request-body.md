# Request Body

Accept and parse JSON request bodies using the `Body()` parameter marker and Zig structs as data models.

## Overview

When a client sends data to your API (typically via POST, PUT, or PATCH), it usually arrives as a JSON body. In Zigmund, you define a Zig struct that describes the expected shape of that JSON, then declare a `Body()` parameter in your handler. The framework deserializes the incoming JSON into your struct, validates the structure, and hands you a fully typed value -- no manual parsing required.

This is the Zigmund equivalent of FastAPI's Pydantic models for request bodies.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// Define the expected JSON structure as a Zig struct.
// Fields with default values are optional in the JSON payload.
const ItemPayload = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true, // Defaults to true if not provided.
};

fn createItem(
    // The Body() marker tells Zigmund to parse the JSON body into ItemPayload.
    item: zigmund.Body(ItemPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = item.value.?.name,
        .price = item.value.?.price,
        .in_stock = item.value.?.in_stock,
    });
}

// Registration -- POST because we are creating a resource.
// app.post("/items", createItem, .{})
```

### Request example

```bash
curl -X POST http://127.0.0.1:8000/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Widget", "price": 9.99}'
```

Response:

```json
{"name": "Widget", "price": 9.99, "in_stock": true}
```

The `in_stock` field was not sent, so it takes the default value defined in the struct.

## How It Works

### 1. Define a model struct

Create a Zig struct whose fields match the JSON keys you expect:

```zig
const ItemPayload = struct {
    name: []const u8,    // Required string field.
    price: f64,          // Required number field.
    in_stock: bool = true, // Optional; defaults to true.
};
```

**Required vs. optional fields:**

| Struct field          | JSON behavior                                     |
|-----------------------|---------------------------------------------------|
| `name: []const u8`    | Must be present in the JSON. Missing = 422 error. |
| `in_stock: bool = true` | May be omitted. Defaults to `true`.             |

### 2. Use Body() in the handler

Wrap your struct type with `zigmund.Body(T, options)`:

```zig
fn createItem(
    item: zigmund.Body(ItemPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
```

The second argument is a `BodyOptions` struct. Passing `.{}` accepts all defaults (JSON media type, no extra validation constraints).

### 3. Access parsed fields

The deserialized struct lives at `item.value.?`:

```zig
const name = item.value.?.name;   // []const u8
const price = item.value.?.price; // f64
```

Like path parameters, `.value` is an optional. For body parameters the value is always present when the handler is called (malformed JSON produces a 422 before the handler runs), so `.?` is safe.

### 4. BodyOptions reference

| Field        | Type           | Default              | Description                                      |
|--------------|----------------|----------------------|--------------------------------------------------|
| `embed`      | `bool`         | `false`              | Nest the body under a key (for multi-body routes).|
| `media_type` | `[]const u8`   | `"application/json"` | Expected Content-Type.                           |
| `description`| `?[]const u8`  | `null`               | Description for OpenAPI docs.                    |
| `gt`, `ge`, `lt`, `le` | `?f64` | `null`          | Numeric validation constraints.                  |
| `min_length` | `?usize`       | `null`               | Minimum string length.                           |
| `max_length` | `?usize`       | `null`               | Maximum string length.                           |

### 5. Multiple body fields and embedding

If a handler needs multiple body parameters, use `.embed = true` so each is nested under its own key:

```zig
fn createOrder(
    item: zigmund.Body(ItemPayload, .{ .embed = true }),
    quantity: zigmund.Body(QuantityPayload, .{ .embed = true }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // JSON input: {"item": {...}, "quantity": {...}}
}
```

## Key Points

- Zig structs serve as data models. There is no separate schema definition language -- the struct *is* the schema.
- Fields without default values are required. Fields with defaults (e.g., `in_stock: bool = true`) are optional in the incoming JSON.
- `Body()` handles JSON deserialization, type checking, and validation before the handler runs. Invalid payloads produce a 422 error.
- The model struct automatically appears in the generated OpenAPI schema, so your API documentation stays in sync with your code.
- Use `app.post`, `app.put`, or `app.patch` for routes that accept request bodies.

## See Also

- [Response Model](response-model.md) -- filter outgoing response fields with a struct.
- [Extra Data Types](extra-data-types.md) -- mapping Zig native types to JSON.
- [Path Parameters](path-parameters.md) -- combine body parsing with URL path values.
- [Query Parameters](query-parameters.md) -- combine body parsing with query string values.
