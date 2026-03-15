const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/response-change-status-code/";

fn createOrUpdate(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const id = item_id.value.?;
    // Simulate: even IDs are existing items (200), odd IDs are new (201 Created)
    if (id % 2 == 0) {
        return zigmund.Response.json(allocator, .{
            .item_id = id,
            .action = "updated",
        });
    }
    return (try zigmund.Response.json(allocator, .{
        .item_id = id,
        .action = "created",
    })).withStatus(.created);
}

fn conditionalNotFound(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const id = item_id.value.?;
    if (id == 0) {
        return (try zigmund.Response.json(allocator, .{
            .detail = "Item not found",
        })).withStatus(.not_found);
    }
    return zigmund.Response.json(allocator, .{
        .item_id = id,
        .name = "Found item",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.put("/advanced/response-change-status-code/items/{item_id}", createOrUpdate, .{
        .summary = "Create or update item with dynamic status code",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_change_status_create_or_update",
        .responses = &.{
            .{ .status_code = .created, .description = "Item created" },
        },
    });
    try app.get("/advanced/response-change-status-code/items/{item_id}", conditionalNotFound, .{
        .summary = "Get item or return 404 dynamically",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_change_status_conditional_not_found",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
        },
    });
}
