const std = @import("std");
const zigmund = @import("zigmund");

const Meta = struct {
    active: bool,
};

const Item = struct {
    id: u32,
    name: []const u8,
    meta: ?Meta = null,
};

fn itemHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = @as(u32, 1),
        .name = "widget",
        .meta = .{ .active = true },
    });
}

test "openapi emits response schema for response_model" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-response-model",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items/{item_id}", itemHandler, .{
        .status_code = .created,
        .response_model = Item,
    });

    try app.get("/items", itemHandler, .{
        .response_model = []const Item,
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/items/{item_id}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"201\":{\"description\":\"Successful Response\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"schemas\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"id\":{\"type\":\"integer\",\"format\":\"int32\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"meta\":{\"type\":\"object\",\"properties\":{\"active\":{\"type\":\"boolean\"}},\"required\":[\"active\"]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"required\":[\"id\",\"name\"]") != null);

    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"200\":{\"description\":\"Successful Response\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/") != null);
}
