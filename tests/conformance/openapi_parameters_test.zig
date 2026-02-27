const std = @import("std");
const zigmund = @import("zigmund");

fn paramsHandler(
    item: zigmund.Path(u64, .{ .alias = "item_id", .description = "Item ID" }),
    page: zigmund.Query(?u32, .{ .alias = "page", .required = true, .deprecated = true, .description = "Page" }),
    token: zigmund.Header(?[]const u8, .{ .alias = "x-token", .description = "Token" }),
    session: zigmund.Cookie([]const u8, .{ .alias = "session_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .item_id = item.value,
        .page = page.value,
        .token = token.value,
        .session = session.value,
    });
}

fn plainHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("ok");
}

test "openapi includes injected query/path/header/cookie parameters" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-params",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items/{item_id}", paramsHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"parameters\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"item_id\",\"in\":\"path\",\"required\":true,\"description\":\"Item ID\",\"schema\":{\"type\":\"integer\",\"format\":\"int64\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"page\",\"in\":\"query\",\"required\":true,\"deprecated\":true,\"description\":\"Page\",\"schema\":{\"type\":\"integer\",\"format\":\"int32\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"x-token\",\"in\":\"header\",\"required\":false,\"description\":\"Token\",\"schema\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"session_id\",\"in\":\"cookie\",\"required\":true,\"schema\":{\"type\":\"string\"}") != null);
}

test "openapi falls back to path placeholder parameters" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-params-fallback",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/plain/{slug}", plainHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"slug\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}") != null);
}

test "openapi path fallback strips converter suffix from placeholder name" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-path-converter",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/assets/{file_path:path}", plainHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"file_path\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}") != null);
}
