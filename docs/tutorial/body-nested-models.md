# Nested Models

Zigmund automatically handles nested Zig structs in JSON request bodies. Define your data model with struct fields that are themselves structs, and Zigmund parses the entire hierarchy from the incoming JSON.

## Overview

APIs often accept complex, hierarchical data -- a user with an embedded address, an order with line items, a configuration with nested sections. In Zigmund, you model these relationships using nested Zig structs. The `Body()` marker parses the full JSON tree into your struct hierarchy in a single step.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip_code: ?[]const u8 = null,
};

const User = struct {
    name: []const u8,
    age: u32,
    address: Address,
};

fn createUser(
    user: zigmund.Body(User, .{
        .description = "User with nested address object",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = user.value.?;
    return zigmund.Response.json(allocator, .{
        .name = body.name,
        .age = body.age,
        .address = .{
            .street = body.address.street,
            .city = body.address.city,
            .zip_code = body.address.zip_code,
        },
    });
}
```

Register the route:

```zig
try app.post("/users", createUser, .{});
```

The endpoint accepts a JSON body like:

```json
{
    "name": "Alice",
    "age": 30,
    "address": {
        "street": "123 Main St",
        "city": "Wonderland",
        "zip_code": "12345"
    }
}
```

## How It Works

1. **Define nested structs.** `Address` is a standalone struct with its own fields. `User` has an `address: Address` field, creating a two-level hierarchy.
2. **Single Body() declaration.** The handler declares `zigmund.Body(User, .{})`. Zigmund parses the entire JSON object, recursively populating both the `User` and its nested `Address`.
3. **Access nested fields.** After unwrapping with `user.value.?`, access nested data through the struct hierarchy: `body.address.street`, `body.address.city`, etc.

## Key Points

- **Arbitrary nesting depth.** Structs can be nested to any depth. A struct field can itself contain another struct, which can contain another, and so on.
- **Optional nested objects.** Make a nested struct field optional with `?Address`. If the JSON omits the `address` key, the field is `null` rather than causing a parse error.
- **Default values.** Individual fields within nested structs can have defaults (e.g., `zip_code: ?[]const u8 = null`). Defaults apply when the key is missing from the JSON.
- **OpenAPI schema generation.** Zigmund generates the full nested JSON Schema in the OpenAPI spec. Documentation tools display the hierarchy clearly, including required/optional markers and descriptions.
- **Validation propagates.** If any required field at any nesting level is missing or has the wrong type, Zigmund returns a structured validation error before the handler runs.
- **Reusable models.** Define common nested structs (like `Address`) once and embed them in multiple parent structs across different endpoints.

## See Also

- [Request Body](request-body.md) -- Basic flat JSON body parsing.
- [Body Fields](body-fields.md) -- Adding validation constraints to body fields.
- [Multiple Body Parameters](body-multiple-params.md) -- Combining body with path and query parameters.
- [Partial Updates](body-updates.md) -- Handling partial updates with optional fields.
