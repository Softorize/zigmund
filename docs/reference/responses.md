# Response Model Reference

## Overview

Zigmund provides response model features that control how route responses are shaped, validated, and documented in the OpenAPI specification.

## ResponseModelAlias

Maps response model field paths to alternative names in the JSON output.

```zig
pub const ResponseModelAlias = struct {
    path: []const u8,
    alias: []const u8,
};
```

| Field | Type | Description |
|-------|------|-------------|
| `path` | `[]const u8` | Dot-separated path to the field (e.g., `"address.street"`) |
| `alias` | `[]const u8` | Alternative field name in the JSON output |

### Usage in Response Models

Define aliases on your struct using the `zigmund_response_aliases` declaration:

```zig
const UserResponse = struct {
    first_name: []const u8,
    last_name: []const u8,
    email_address: []const u8,

    pub const zigmund_response_aliases: []const zigmund.ResponseModelAlias = &.{
        .{ .path = "first_name", .alias = "firstName" },
        .{ .path = "last_name", .alias = "lastName" },
        .{ .path = "email_address", .alias = "email" },
    };
};
```

## ComputedFieldFn

A function that computes a field value from the existing response object.

```zig
pub const ComputedFieldFn = *const fn (std.json.ObjectMap, std.mem.Allocator) anyerror!std.json.Value
```

## ComputedFieldEntry

Associates a computed field name with its computation function.

```zig
pub const ComputedFieldEntry = struct {
    name: []const u8,
    compute: ComputedFieldFn,
};
```

### Usage in Response Models

Define computed fields using the `zigmund_computed_fields` declaration:

```zig
const OrderResponse = struct {
    subtotal: f64,
    tax: f64,

    pub const zigmund_computed_fields: []const zigmund.ComputedFieldEntry = &.{
        .{
            .name = "total",
            .compute = computeTotal,
        },
    };

    fn computeTotal(obj: std.json.ObjectMap, allocator: std.mem.Allocator) !std.json.Value {
        _ = allocator;
        const subtotal = obj.get("subtotal").?.float;
        const tax = obj.get("tax").?.float;
        return .{ .float = subtotal + tax };
    }
};
```

## Response Transform and Validate

### Transform

Define a `zigmund_response_transform` declaration on your response model struct to modify the JSON value before it is sent:

```zig
pub fn zigmund_response_transform(value: *std.json.Value, allocator: std.mem.Allocator) !void {
    // Modify the JSON value tree
}
```

### Validate

Define a `zigmund_response_validate` declaration to validate the JSON value before sending:

```zig
pub fn zigmund_response_validate(value: *const std.json.Value, allocator: std.mem.Allocator) !void {
    // Return an error to reject the response
}
```

## RouteOptions Response Model Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `response_model` | `?type` | `null` | Zig struct type for OpenAPI response schema |
| `response_model_include` | `[]const []const u8` | `&.{}` | Only include these fields |
| `response_model_exclude` | `[]const []const u8` | `&.{}` | Exclude these fields |
| `response_model_by_alias` | `bool` | `true` | Use alias names in output |
| `response_model_exclude_unset` | `bool` | `false` | Exclude fields not set |
| `response_model_exclude_defaults` | `bool` | `false` | Exclude fields at default values |
| `response_model_exclude_none` | `bool` | `false` | Exclude null-valued fields |

## Example

```zig
try app.get("/orders/{id}", getOrder, .{
    .response_model = OrderResponse,
    .response_model_exclude = &.{"internal_notes"},
    .response_model_exclude_none = true,
});
```
