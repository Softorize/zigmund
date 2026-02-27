const std = @import("std");
const zigmund = @import("zigmund");

const InventoryError = error{ItemUnavailable};

fn readInventoryItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (item_id.value.? == 0) {
        return InventoryError.ItemUnavailable;
    }

    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .available = true,
    });
}

fn inventoryErrorHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    _ = err;
    var response = try zigmund.Response.json(allocator, .{
        .detail = "Item is unavailable",
    });
    return response.withStatus(.not_found);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addExceptionHandler(InventoryError, inventoryErrorHandler);
    try app.get("/tutorial/handling-errors/items/{item_id}", readInventoryItem, .{
        .summary = "Handle route errors with exception handlers",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_read_inventory_item_with_error_handler",
    });
}
