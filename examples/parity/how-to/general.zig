const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/general/";

/// Demonstrates common Zigmund patterns: creating an app, registering
/// routes with different HTTP methods, adding metadata, and using
/// typed parameters.

fn appInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "General Zigmund patterns",
        .patterns = .{
            .create_app = "zigmund.App.init(allocator, .{ .title = \"...\", .version = \"...\" })",
            .register_route = "app.get(\"/path\", handler, .{ .summary = \"...\" })",
            .http_methods = "app.get, app.post, app.put, app.patch, app.delete",
            .path_params = "Use {param_name} in path, zigmund.Path(type, .{}) in handler",
            .query_params = "Use zigmund.Query(type, .{}) in handler",
            .json_body = "Use zigmund.Body(StructType, .{}) in handler",
            .json_response = "zigmund.Response.json(allocator, value)",
        },
    });
}

fn getItems(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .items = &[_][]const u8{ "item-1", "item-2", "item-3" },
    });
}

fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .item_id = item_id.value.?,
        .name = "Example item",
    });
}

fn createItem(
    body: zigmund.Body(struct { name: []const u8, price: f64 }, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .page = source_page,
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
        .page = source_page,
        .query = q.value orelse "all",
        .limit = limit.value orelse 10,
        .results = &[_][]const u8{ "result-1", "result-2" },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/general", appInfo, .{
        .summary = "General Zigmund patterns overview",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_general_info",
    });

    try app.get("/how-to/general/items", getItems, .{
        .summary = "List items (GET example)",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_general_list_items",
    });

    try app.get("/how-to/general/items/{item_id}", getItem, .{
        .summary = "Get item by ID (path parameter example)",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_general_get_item",
    });

    try app.post("/how-to/general/items", createItem, .{
        .summary = "Create item (POST with JSON body example)",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_general_create_item",
    });

    try app.get("/how-to/general/search", searchItems, .{
        .summary = "Search items (query parameters example)",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_general_search_items",
    });
}
