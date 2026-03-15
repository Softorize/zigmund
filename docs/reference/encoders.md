# Encoders Reference

## Overview

`jsonableEncode` converts complex Zig values into a `std.json.Value` tree that can be further manipulated or serialized. This is the Zig equivalent of FastAPI's `jsonable_encoder`.

## jsonableEncode

```zig
pub fn jsonableEncode(allocator: std.mem.Allocator, value: anytype) !std.json.Value
```

Recursively converts a Zig value into a `std.json.Value` tree.

### Supported Types

| Zig Type | JSON Type | Notes |
|----------|-----------|-------|
| `null` | `null` | |
| `?T` (optional) | value or `null` | Unwraps if present, null otherwise |
| `bool` | `bool` | |
| integers (all widths) | `integer` (i64) | Cast to i64 |
| floats (all widths) | `float` (f64) | Cast to f64 |
| `[]const u8` | `string` | |
| slices (non-string) | `array` | Each element recursively encoded |
| structs | `object` | Each field becomes a key-value pair |
| enums | `string` | Uses the tag name |

### Return Value

Returns a `std.json.Value` which is a tagged union:

```zig
pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    number_string: []const u8,
    string: []const u8,
    array: Array,
    object: ObjectMap,
};
```

### Memory Management

- Strings are **not** copied -- they reference the original data.
- Arrays and objects allocate using the provided allocator and must be freed by the caller.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const User = struct {
    name: []const u8,
    age: i32,
    active: bool,
    tags: []const []const u8,
};

fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    const user = User{
        .name = "Alice",
        .age = 30,
        .active = true,
        .tags = &.{ "admin", "editor" },
    };

    var encoded = try zigmund.jsonableEncode(allocator, user);
    defer encoded.object.deinit();

    // Manipulate the JSON tree
    try encoded.object.put("extra", .{ .string = "computed" });

    // Serialize to string
    const json_str = try std.json.stringifyAlloc(allocator, encoded, .{});
    defer allocator.free(json_str);

    return zigmund.Response.json(allocator, user);
}
```

For most use cases, `Response.json(allocator, value)` directly serializes Zig values to JSON without needing `jsonableEncode`. Use `jsonableEncode` when you need to inspect or modify the JSON tree before serialization.
