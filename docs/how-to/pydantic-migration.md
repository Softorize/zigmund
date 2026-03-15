# Migrating from Other Frameworks

This guide explains how Zigmund handles data modeling compared to frameworks like FastAPI (Python) that use runtime validation libraries such as Pydantic.

## Problem

You are coming from a framework that uses runtime data validation (like FastAPI with Pydantic) and want to understand how Zigmund handles models, validation, and serialization.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// In Zigmund, a plain Zig struct replaces Pydantic's BaseModel
const UserModel = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    is_active: bool = true, // Default values work like Pydantic field defaults
};

fn createUser(
    body: zigmund.Body(UserModel, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = body.value.?;
    return zigmund.Response.json(allocator, .{
        .id = user.id,
        .name = user.name,
        .email = user.email,
        .is_active = user.is_active,
    });
}

fn getUser(allocator: std.mem.Allocator) !zigmund.Response {
    const user = UserModel{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .is_active = true,
    };
    return zigmund.Response.json(allocator, user);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    try app.post("/users", createUser, .{
        .response_model = UserModel,
    });

    try app.get("/users/1", getUser, .{
        .response_model = UserModel,
    });

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

Zigmund uses Zig's native type system in place of runtime validation libraries. Here is how concepts map:

| Pydantic / FastAPI | Zigmund Equivalent |
|--------------------|--------------------|
| `class UserModel(BaseModel):` | `const UserModel = struct { ... };` |
| `field: str` (required) | `field: []const u8` |
| `field: Optional[str] = None` | `field: ?[]const u8 = null` |
| `field: int = 42` | `field: i32 = 42` |
| `field: bool = True` | `field: bool = true` |
| Field validators | Compile-time type checking + parameter constraints (`gt`, `le`, `min_length`, etc.) |
| `response_model=UserModel` | `.response_model = UserModel` |
| `jsonable_encoder()` | `zigmund.jsonableEncode()` |
| JSON serialization | `zigmund.Response.json(allocator, value)` (automatic) |

Key differences:
- **Compile-time validation** -- Zig's type system catches type mismatches at compile time rather than at runtime.
- **No migration needed** -- There is no Pydantic v1 to v2 migration concern. Define Zig structs and the framework handles the rest.
- **Zero runtime overhead** -- Struct definitions have no runtime cost for schema introspection.
- **Optional fields** -- Use Zig's `?T` optional type syntax instead of Python's `Optional[T]`.

## See Also

- [Parameters Reference](../reference/parameters.md)
- [Responses Reference](../reference/responses.md)
- [Encoders Reference](../reference/encoders.md)
