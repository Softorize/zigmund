const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/additional-status-codes/";

fn createItem(allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .name = "New item",
        .status = "created",
    })).withStatus(.created);
}

fn deleteItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
) zigmund.Response {
    _ = item_id;
    return zigmund.Response.text("").withStatus(.no_content);
}

fn updateItem(
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
        .name = "Updated item",
    });
}

fn acceptedTask(allocator: std.mem.Allocator) !zigmund.Response {
    return (try zigmund.Response.json(allocator, .{
        .task_id = "abc-123",
        .status = "processing",
    })).withStatus(.accepted);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/advanced/additional-status-codes/items", createItem, .{
        .summary = "Create an item with 201 Created status",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_status_create_item",
        .status_code = .created,
    });
    try app.delete("/advanced/additional-status-codes/items/{item_id}", deleteItem, .{
        .summary = "Delete an item with 204 No Content status",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_status_delete_item",
        .status_code = .no_content,
    });
    try app.put("/advanced/additional-status-codes/items/{item_id}", updateItem, .{
        .summary = "Update an item or return 404",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_status_update_item",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
        },
    });
    try app.post("/advanced/additional-status-codes/tasks", acceptedTask, .{
        .summary = "Start a background task with 202 Accepted",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_status_accepted_task",
        .status_code = .accepted,
    });
}
