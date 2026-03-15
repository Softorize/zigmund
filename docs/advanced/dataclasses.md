# Dataclasses

Zig structs serve as the natural equivalent of Python dataclasses. They support default field values, are used directly as `Body` parameters for automatic JSON deserialization, and generate OpenAPI schemas at compile time.

## Overview

In Python/FastAPI, dataclasses and Pydantic models define the shape of request and response data. In Zig, plain `struct` types fill this role. Zig structs support default values, optional fields (using `?` types), and compile-time reflection -- making them a direct replacement for Python dataclasses without any runtime overhead.

When a struct is used as a `zigmund.Body()` parameter, the framework automatically deserializes the incoming JSON into the struct, validates required fields, and generates an OpenAPI schema from the struct definition.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Zig structs are the natural equivalent of Python dataclasses.
/// They support default values, are used directly as Body parameters
/// for automatic JSON deserialization, and generate OpenAPI schemas.

const Item = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: f64 = 0.0,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(Item, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const data = item.value.?;

    const total = data.price + data.tax;

    var response = try zigmund.Response.json(allocator, .{
        .name = data.name,
        .description = data.description,
        .price = data.price,
        .tax = data.tax,
        .total = total,
        .in_stock = data.in_stock,
        .message = "Zig struct with defaults — equivalent of Python dataclass",
    });
    return response.withStatus(.created);
}

fn getDefaultItem(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    // Show default values from the struct definition
    const defaults: Item = .{
        .name = "Example",
        .price = 0.0,
    };

    return zigmund.Response.json(allocator, .{
        .name = defaults.name,
        .description = defaults.description,
        .price = defaults.price,
        .tax = defaults.tax,
        .in_stock = defaults.in_stock,
        .message = "Struct defaults mirror Python dataclass field defaults",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/items", createItem, .{
        .summary = "Create item using Zig struct (dataclass equivalent) as Body",
    });

    try app.get("/items/defaults", getDefaultItem, .{
        .summary = "Show struct default values (dataclass defaults equivalent)",
    });
}
```

## How It Works

### 1. Defining a Struct (Dataclass Equivalent)

A Zig struct with default values maps directly to a Python dataclass:

```zig
const Item = struct {
    name: []const u8,              // required field (no default)
    description: ?[]const u8 = null, // optional field with null default
    price: f64,                    // required field
    tax: f64 = 0.0,               // field with default value
    in_stock: bool = true,         // field with default value
};
```

| Python Dataclass              | Zig Struct                       |
|-------------------------------|----------------------------------|
| `name: str`                   | `name: []const u8`               |
| `description: Optional[str]`  | `description: ?[]const u8 = null`|
| `price: float`                | `price: f64`                     |
| `tax: float = 0.0`           | `tax: f64 = 0.0`                |
| `in_stock: bool = True`      | `in_stock: bool = true`         |

### 2. Using Structs as Body Parameters

When you declare a `zigmund.Body(Item, .{})` parameter, the framework:

1. Reads the raw JSON from the request body.
2. Deserializes it into an `Item` struct using `std.json`.
3. Applies default values for any missing fields.
4. Returns a 422 error if required fields are missing or types are wrong.
5. Generates an OpenAPI schema from the struct definition.

```zig
fn createItem(
    item: zigmund.Body(Item, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const data = item.value.?;
    // data.name, data.price are guaranteed to be present
    // data.description might be null
    // data.tax defaults to 0.0 if not provided
}
```

### 3. Default Values and Initialization

Zig structs with default values can be partially initialized:

```zig
const defaults: Item = .{
    .name = "Example",
    .price = 0.0,
    // .description defaults to null
    // .tax defaults to 0.0
    // .in_stock defaults to true
};
```

This mirrors Python's `Item(name="Example", price=0.0)` where unspecified fields use their defaults.

### 4. OpenAPI Schema Generation

Zigmund reflects on the struct at compile time to generate an OpenAPI schema. The generated schema includes:

- Field names and types.
- Required vs. optional fields (fields with defaults are optional in the schema).
- The `nullable` attribute for `?` types.

## Key Points

- Zig structs are the idiomatic replacement for Python dataclasses -- no additional library needed.
- Default values in structs work identically to Python dataclass field defaults.
- Optional fields use Zig's `?` (optional) type, equivalent to Python's `Optional[T]`.
- `zigmund.Body()` automatically deserializes JSON into structs and validates required fields.
- OpenAPI schemas are generated at compile time from struct definitions -- no runtime reflection.
- Structs can be nested: a struct field can itself be another struct.

## See Also

- [Advanced Python Types](advanced-python-types.md) -- Zig equivalents of Union, Generic, and other advanced Python types.
- [Response Directly](response-directly.md) -- return structs as JSON responses.
- [Strict Content Type](strict-content-type.md) -- validate content types for body deserialization.
