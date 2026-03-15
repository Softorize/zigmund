const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/body-multiple-params/";

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
        .source = source_page,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.put("/tutorial/body-multiple-params/items/{item_id}", updateItem, .{
        .summary = "Update an item using path, query, and body parameters together",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_update_item_with_multiple_params",
    });
}
