const std = @import("std");
const zigmund = @import("zigmund");

const ItemPayload = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(ItemPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = item.value.?.name,
        .price = item.value.?.price,
        .in_stock = item.value.?.in_stock,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/body/items", createItem, .{
        .summary = "Create an item from JSON body",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_create_item_from_body",
    });
}
