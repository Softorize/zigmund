# How to Build a Basic Zigmund Application

This recipe covers the fundamental patterns for creating apps, registering routes, and handling typed parameters.

## Problem

You want to create a Zigmund web application with routes that handle different HTTP methods, path parameters, query parameters, and JSON request/response bodies.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn getItems(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .items = &[_][]const u8{ "item-1", "item-2", "item-3" },
    });
}

fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .name = "Example item",
    });
}

fn createItem(
    body: zigmund.Body(struct { name: []const u8, price: f64 }, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .created = .{
            .name = body.value.?.name,
            .price = body.value.?.price,
        },
    })).withStatus(.created);
}

fn searchItems(
    q: zigmund.Query([]const u8, .{ .alias = "q" }),
    limit: zigmund.Query(u32, .{ .alias = "limit" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .query = q.value orelse "all",
        .limit = limit.value orelse 10,
        .results = &[_][]const u8{ "result-1", "result-2" },
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    try app.get("/items", getItems, .{
        .summary = "List items",
    });
    try app.get("/items/{item_id}", getItem, .{
        .summary = "Get item by ID",
    });
    try app.post("/items", createItem, .{
        .summary = "Create item",
    });
    try app.get("/search", searchItems, .{
        .summary = "Search items",
    });

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

1. **App initialization** -- `App.init` takes an allocator and an `AppConfig` with at minimum a `title` and `version`.
2. **Route registration** -- Use `app.get`, `app.post`, `app.put`, `app.patch`, `app.delete`, `app.options`, `app.head`, or `app.trace` to register handlers at a path. Each call takes a path string, a handler function, and `RouteOptions` (summary, tags, operation_id, etc.).
3. **Path parameters** -- Use `{param_name}` in the path string and declare a `zigmund.Path(T, .{ .alias = "param_name" })` parameter in the handler. The framework injects the parsed value automatically.
4. **Query parameters** -- Declare `zigmund.Query(T, .{ .alias = "param_name" })` parameters. Optional values use `orelse` for defaults.
5. **JSON body** -- Declare `zigmund.Body(StructType, .{})` to automatically parse the request body into the given struct type.
6. **JSON response** -- `zigmund.Response.json(allocator, value)` serializes any Zig value to JSON.
7. **Status codes** -- Chain `.withStatus(.created)` on a response to set the HTTP status.

## See Also

- [Request Reference](../reference/request.md)
- [Response Reference](../reference/response.md)
- [Parameters Reference](../reference/parameters.md)
- [App Reference](../reference/app.md)
