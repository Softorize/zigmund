const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/additional-responses/";

fn getItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const id = item_id.value.?;
    if (id == 0) {
        return (zigmund.Response.json(allocator, .{
            .message = "Item not found",
        }) catch unreachable).withStatus(.not_found);
    }
    return zigmund.Response.json(allocator, .{
        .item_id = id,
        .name = "Widget",
        .description = "A useful widget",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/additional-responses/items/{item_id}", getItem, .{
        .summary = "Get item with additional response specifications",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_additional_responses_get_item",
        .responses = &.{
            .{ .status_code = .not_found, .description = "Item not found" },
            .{ .status_code = .bad_request, .description = "Invalid item ID" },
        },
    });
}
