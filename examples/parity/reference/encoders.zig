const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/encoders/";

const Product = struct {
    id: u32,
    name: []const u8,
    price: f64,
    in_stock: bool,
};

/// Demonstrates JSON encoding patterns: Response.json auto-serializes structs.
fn encoderDemo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    // Response.json uses std.json.fmt internally to serialize any Zig value
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .product = Product{
            .id = 1,
            .name = "Widget",
            .price = 9.99,
            .in_stock = true,
        },
        .encoding = .{
            .method = "Response.json(allocator, value) - auto-serializes any struct/tuple",
            .format = "Uses std.json.fmt with std.fmt.allocPrint",
            .content_type = "application/json",
            .nested = "Nested structs, arrays, and optionals are fully supported",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/encoders", encoderDemo, .{
        .summary = "JSON encoding: struct serialization via Response.json",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_encoders_json",
    });
}
