const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/body-updates/";

const ItemFull = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: ?f64 = null,
};

const ItemPartial = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    price: ?f64 = null,
    tax: ?f64 = null,
};

fn replaceItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    item: zigmund.Body(ItemFull, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .operation = "replace",
        .item_id = item_id.value.?,
        .name = body.name,
        .description = body.description,
        .price = body.price,
        .tax = body.tax,
        .source = source_page,
    });
}

fn patchItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    item: zigmund.Body(ItemPartial, .{
        .description = "Partial item update: only provided fields are changed",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = item.value.?;
    return zigmund.Response.json(allocator, .{
        .operation = "partial_update",
        .item_id = item_id.value.?,
        .name = body.name,
        .description = body.description,
        .price = body.price,
        .tax = body.tax,
        .source = source_page,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.put("/tutorial/body-updates/items/{item_id}", replaceItem, .{
        .summary = "Replace an item entirely via PUT",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_replace_item_put",
    });
    try app.patch("/tutorial/body-updates/items/{item_id}", patchItem, .{
        .summary = "Partially update an item via PATCH",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_partial_update_item_patch",
    });
}
