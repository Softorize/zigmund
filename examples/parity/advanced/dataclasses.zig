const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/dataclasses/";

/// Zig structs are the natural equivalent of Python dataclasses.
/// They support default values, are used directly as Body parameters
/// for automatic JSON deserialization, and generate OpenAPI schemas.

const Item = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    price: f64,
    tax: f64 = 0.0,
    in_stock: bool = true,
};

fn createItem(
    item: zigmund.Body(Item, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const data = item.value.?;

    const total = data.price + data.tax;

    var response = try zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = data.name,
        .description = data.description,
        .price = data.price,
        .tax = data.tax,
        .total = total,
        .in_stock = data.in_stock,
        .message = "Zig struct with defaults — equivalent of Python dataclass",
    });
    return response.withStatus(.created);
}

fn getDefaultItem(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    // Show default values from the struct definition
    const defaults: Item = .{
        .name = "Example",
        .price = 0.0,
    };

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .name = defaults.name,
        .description = defaults.description,
        .price = defaults.price,
        .tax = defaults.tax,
        .in_stock = defaults.in_stock,
        .message = "Struct defaults mirror Python dataclass field defaults",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/advanced/dataclasses", createItem, .{
        .summary = "Create item using Zig struct (dataclass equivalent) as Body",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_dataclasses_create",
    });

    try app.get("/advanced/dataclasses", getDefaultItem, .{
        .summary = "Show struct default values (dataclass defaults equivalent)",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_dataclasses_defaults",
    });
}
