# Custom JSON Encoding

Serialize complex Zig types -- structs with nested objects, enums, optionals, floats, and slices -- into clean JSON responses using Zigmund's built-in encoder.

## Overview

Zigmund uses Zig's standard library JSON serialization under the hood, enhanced with sensible defaults for web APIs. When you call `zigmund.Response.json(allocator, value)`, the framework serializes the value into a JSON byte stream, sets the `Content-Type` header to `application/json`, and returns it to the client.

The encoder handles all standard Zig types:

| Zig Type              | JSON Representation                          |
|-----------------------|----------------------------------------------|
| `struct`              | Object with field names as keys.             |
| `enum`                | String (the tag name, e.g., `"high"`).       |
| `?T` (optional)       | The value if present, `null` if `null`.      |
| `bool`                | `true` / `false`.                            |
| Integers / `f32`/`f64`| JSON number.                                 |
| `[]const u8`          | JSON string.                                 |
| `[]const T`           | JSON array.                                  |
| Nested structs        | Nested JSON objects.                         |

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const Priority = enum {
    low,
    medium,
    high,
};

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip_code: ?[]const u8 = null,
};

const UserProfile = struct {
    id: u32,
    name: []const u8,
    email: ?[]const u8 = null,
    is_active: bool,
    score: f64,
    priority: Priority,
    address: Address,
    tags: []const []const u8,
};

fn getEncodedProfile(allocator: std.mem.Allocator) !zigmund.Response {
    const profile = UserProfile{
        .id = 42,
        .name = "Alice",
        .email = "alice@example.com",
        .is_active = true,
        .score = 98.5,
        .priority = .high,
        .address = .{
            .street = "123 Main St",
            .city = "Springfield",
            .zip_code = "62704",
        },
        .tags = &.{ "admin", "verified" },
    };
    return zigmund.Response.json(allocator, profile);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/encoder", getEncodedProfile, .{
        .summary = "JSON encoding of complex types (structs, enums, optionals)",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_encoder_profile",
    });
}
```

The response body produced by this handler:

```json
{
  "id": 42,
  "name": "Alice",
  "email": "alice@example.com",
  "is_active": true,
  "score": 98.5,
  "priority": "high",
  "address": {
    "street": "123 Main St",
    "city": "Springfield",
    "zip_code": "62704"
  },
  "tags": ["admin", "verified"]
}
```

## How It Works

1. **Define your types.** Zig structs map directly to JSON objects. Nest structs freely -- `UserProfile` contains an `Address` struct, which becomes a nested JSON object.

2. **Use enums for constrained values.** The `Priority` enum serializes as the tag name string (`"low"`, `"medium"`, `"high"`), not as an integer. This produces readable, self-documenting JSON.

3. **Handle optionals naturally.** `email: ?[]const u8 = null` serializes as `null` when not set. When populated, it serializes as a normal string.

4. **Serialize slices as arrays.** `tags: []const []const u8` becomes a JSON array of strings. Any `[]const T` slice becomes a JSON array.

5. **Call `Response.json`.** Pass any serializable value to `zigmund.Response.json(allocator, value)`. The framework allocates the JSON buffer, sets `Content-Type: application/json`, and wraps it in a `Response`.

## Key Points

- `Response.json` works with anonymous structs (`.{ .key = value }`) and named structs alike. Anonymous structs are convenient for ad-hoc responses; named structs provide reusable, documented schemas.
- Enum values serialize as lowercase strings matching the Zig tag name. If your API requires different casing, define the enum tags accordingly.
- Floating-point values serialize with standard JSON number formatting. Zig's `f64` provides sufficient precision for most API use cases.
- The allocator passed to `Response.json` is used for the serialization buffer. Zigmund manages its lifetime -- you do not need to free it manually.
- For complete control over JSON output, you can build a `[]const u8` yourself and return `Response.raw(allocator, json_bytes, "application/json")`.
- The generated OpenAPI schema reflects nested struct types, enum variants, and optional fields accurately.

## See Also

- [Request Body](request-body.md) -- The reverse direction: deserializing JSON into Zig structs.
- [Response Model](response-model.md) -- Control which fields appear in the response.
- [Extra Models](extra-models.md) -- Use different structs for input and output encoding.
- [Stream JSON Lines](stream-json-lines.md) -- Streaming JSON output for large or real-time datasets.
