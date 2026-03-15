# How to Use Separate Input and Output Schemas

This recipe shows how to define distinct request and response types for clean OpenAPI schema generation.

## Problem

You want the OpenAPI specification to generate separate schemas for what clients send (input) versus what they receive (output), giving fine-grained control over your API contract.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// Separate input type (what the client sends)
const CreateItemRequest = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

// Separate output type (what the client receives)
const ItemResponse = struct {
    id: u32,
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
    price_with_tax: f64,
};

fn createItem(
    body: zigmund.Body(CreateItemRequest, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const input = body.value.?;
    const tax = input.tax orelse 0.0;
    return (try zigmund.Response.json(allocator, .{
        .id = @as(u32, 1),
        .name = input.name,
        .description = input.description,
        .price = input.price,
        .tax = input.tax,
        .price_with_tax = input.price + tax,
    })).withStatus(.created);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    try app.post("/items", createItem, .{
        .summary = "Create item",
        .response_model = ItemResponse,
        .status_code = .created,
    });

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

**Recommended approach:** Use different Zig struct types for input and output:

- The `Body(T, .{})` parameter marker defines the request body schema. Zigmund generates an input schema from `T`.
- The `response_model` field in `RouteOptions` defines the response schema. Zigmund generates an output schema from that type.

Because `CreateItemRequest` and `ItemResponse` are different types, the OpenAPI spec will contain two distinct schemas with different fields.

**Dual-use types:** If you use the same struct for both `Body(T)` and `response_model = T`, the OpenAPI generator automatically emits `T_Input` and `T_Output` schemas so that code generators produce distinct client classes:

```zig
const SharedItem = struct {
    name: []const u8,
    price: f64,
    active: bool = true,
};

fn updateSharedItem(
    body: zigmund.Body(SharedItem, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // ...
}

try app.put("/shared", updateSharedItem, .{
    .response_model = SharedItem,
});
```

## See Also

- [OpenAPI Reference](../reference/openapi.md)
- [Parameters Reference](../reference/parameters.md)
- [Responses Reference](../reference/responses.md)
