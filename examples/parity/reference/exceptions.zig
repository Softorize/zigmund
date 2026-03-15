const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/exceptions/";

const ItemError = error{ItemNotFound};

/// Handler that may return a domain error.
fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    if (item_id.value.? == 0) {
        return ItemError.ItemNotFound;
    }
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .id = item_id.value.?,
        .name = "Widget",
    });
}

/// Exception handler registered via app.addExceptionHandler.
/// Catches ItemError and returns a structured JSON error response.
fn itemErrorHandler(
    req: *zigmund.Request,
    err: anyerror,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    _ = err;
    return (try zigmund.Response.json(allocator, .{
        .detail = "Item not found",
        .error_type = "ItemNotFound",
    })).withStatus(.not_found);
}

pub fn buildExample(app: *zigmund.App) !void {
    // Register exception handler for ItemError
    try app.addExceptionHandler(ItemError, itemErrorHandler);

    try app.get("/reference/exceptions/items/{item_id}", getItem, .{
        .summary = "Exception handlers and HTTPException patterns",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_exceptions_get_item",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
        },
    });
}
