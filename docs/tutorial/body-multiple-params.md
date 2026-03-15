# Multiple Body Parameters

Zigmund lets you combine path parameters, query parameters, and a JSON body in a single handler. Each parameter source is declared with its own marker type, and Zigmund resolves them all automatically.

## Overview

Real-world endpoints often need data from multiple sources: an item ID from the URL path, an optional filter from the query string, and the update payload from the request body. Zigmund's parameter markers -- `Path()`, `Query()`, and `Body()` -- can coexist in the same handler signature, each extracting its value from the appropriate part of the request.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const ItemData = struct {
    name: []const u8,
    price: f64,
    is_offer: bool = false,
};

fn updateItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    q: zigmund.Query([]const u8, .{ .alias = "q", .required = false }),
    item: zigmund.Body(ItemData, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .q = q.value,
        .name = body.name,
        .price = body.price,
        .is_offer = body.is_offer,
    });
}
```

Register the route:

```zig
try app.put("/items/{item_id}", updateItem, .{});
```

## How It Works

1. **Path parameter.** `zigmund.Path(u32, .{ .alias = "item_id" })` extracts the `{item_id}` segment from the URL and parses it as a `u32`.
2. **Query parameter.** `zigmund.Query([]const u8, .{ .alias = "q", .required = false })` reads the `?q=...` query string parameter. Because `.required = false`, the handler still works when `q` is omitted.
3. **Body parameter.** `zigmund.Body(ItemData, .{})` parses the JSON request body into an `ItemData` struct.
4. **All resolved together.** Zigmund resolves all three before calling the handler. If any required parameter is missing or invalid, an error response is returned automatically.

A request like `PUT /items/42?q=search` with body `{"name":"Gadget","price":9.99}` would populate all three parameters.

## Key Points

- **Parameter source is explicit.** `Path()`, `Query()`, and `Body()` each declare exactly where the value comes from. There is no ambiguity.
- **Default values.** The `ItemData` struct uses `is_offer: bool = false` as a default. If the JSON body omits `is_offer`, it defaults to `false`.
- **Optional query params.** Setting `.required = false` makes the query parameter optional. The `q.value` will be `null` if not provided.
- **Single body only.** A handler can have at most one `Body()` parameter. If you need multiple JSON objects, nest them inside a single struct.
- **Order does not matter.** Parameters can appear in any order in the handler signature. Zigmund resolves them by type, not position (except for `std.mem.Allocator`, which is always provided).

## See Also

- [Body Fields](body-fields.md) -- Adding validation constraints to body fields.
- [Nested Models](body-nested-models.md) -- Using nested structs for complex JSON payloads.
- [Path Parameters](path-parameters.md) -- Working with path parameters in detail.
- [Query Parameters](query-parameters.md) -- Working with query parameters in detail.
