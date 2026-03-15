const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/body-fields/";

const ItemCreate = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

fn createItem(
    item: zigmund.Body(ItemCreate, .{
        .description = "Item with field validation: price must be > 0, name min 1 char",
        .gt = 0,
        .min_length = 1,
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .name = body.name,
        .description = body.description,
        .price = body.price,
        .tax = body.tax,
        .source = source_page,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/body-fields/items", createItem, .{
        .summary = "Create an item with body field validation constraints",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_create_item_with_field_validation",
    });
}
