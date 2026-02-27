const std = @import("std");
const zigmund = @import("zigmund");

fn readItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item_id.value.?,
        .route = "path-params",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-params/items/{item_id}", readItem, .{
        .summary = "Read an item by path parameter",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_read_item_by_path_param",
    });
}
