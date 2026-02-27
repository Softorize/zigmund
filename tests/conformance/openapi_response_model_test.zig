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

test "default_response_class influences openapi default response content type" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-default-response-class",
        .version = "0.0.1",
    });
    defer app.deinit();

    const H = struct {
        fn run(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
            _ = req;
            _ = allocator;
            return zigmund.Response.text("ok");
        }
    };

    try app.get("/plain", H.run, .{
        .default_response_class = "PlainTextResponse",
    });
    try app.get("/sse", H.run, .{
        .default_response_class = "EventSourceResponse",
    });
    try app.get("/unknown", H.run, .{
        .default_response_class = "UnknownCustomResponse",
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/plain\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"text/plain; charset=utf-8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/sse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"text/event-stream; charset=utf-8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/unknown\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"application/json\"") != null);
}
