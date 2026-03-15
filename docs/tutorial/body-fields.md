# Body Fields

Zigmund supports field-level validation on JSON request bodies. Pass constraint options to the `zigmund.Body()` marker to enforce rules like minimum length, numeric bounds, and required descriptions.

## Overview

When accepting structured data from clients, validation is essential. Rather than writing manual checks in every handler, you can declare constraints directly in the `Body()` marker options. Zigmund validates the incoming data before your handler runs and returns a structured error response if any constraint is violated.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const ItemCreate = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

fn createItem(
    item: zigmund.Body(ItemCreate, .{
        .description = "Item with field validation: price must be > 0, name min 1 char",
        .gt = 0,
        .min_length = 1,
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .name = body.name,
        .description = body.description,
        .price = body.price,
        .tax = body.tax,
    });
}
```

Register the route:

```zig
try app.post("/items", createItem, .{});
```

## How It Works

1. **Define the body struct.** `ItemCreate` declares the expected fields with their types. Optional fields use `?` types with defaults.
2. **Add validation options.** The second argument to `Body()` accepts constraint options:
   - `.description` -- a human-readable description that appears in the OpenAPI schema.
   - `.gt = 0` -- numeric fields must be greater than 0.
   - `.min_length = 1` -- string fields must have at least 1 character.
3. **Automatic validation.** Zigmund validates the parsed body against these constraints before calling the handler. Invalid input produces a 422 response with details about which constraint was violated.

## Key Points

- **Constraint options.** Available validation options include:
  - `.gt` / `.ge` -- greater than / greater than or equal to (numeric fields).
  - `.lt` / `.le` -- less than / less than or equal to (numeric fields).
  - `.min_length` / `.max_length` -- string length bounds.
  - `.description` -- schema description for OpenAPI documentation.
- **Optional fields.** Fields typed as `?T` (e.g., `?[]const u8`, `?f64`) are optional. They default to `null` if not present in the JSON body.
- **OpenAPI integration.** The `.description` and constraint values are reflected in the generated OpenAPI schema, so API documentation tools like Swagger UI display validation rules to consumers.
- **Fail fast.** Validation runs before the handler. If the body is invalid, the handler is never called, preventing business logic from operating on bad data.
- **Struct-level constraints.** The constraints in the `Body()` options apply to the body as a whole. For per-field constraints, define them as part of the struct's field metadata or use nested validation.

## See Also

- [Request Body](request-body.md) -- Basic JSON body parsing without validation.
- [Multiple Body Parameters](body-multiple-params.md) -- Combining body with path and query parameters.
- [Nested Models](body-nested-models.md) -- Validating complex nested JSON structures.
- [Partial Updates](body-updates.md) -- Using optional fields for PATCH operations.
