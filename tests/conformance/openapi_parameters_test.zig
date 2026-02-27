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

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, idx, needle)) |pos| {
        count += 1;
        idx = pos + needle.len;
    }
    return count;
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
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/parameters/path_item_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/parameters/query_page\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/parameters/header_x_token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/parameters/cookie_session_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"path_item_id\":{\"name\":\"item_id\",\"in\":\"path\",\"required\":true,\"description\":\"Item ID\",\"schema\":{\"type\":\"integer\",\"format\":\"int64\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_page\":{\"name\":\"page\",\"in\":\"query\",\"required\":true,\"deprecated\":true,\"description\":\"Page\",\"schema\":{\"type\":\"integer\",\"format\":\"int32\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"header_x_token\":{\"name\":\"x-token\",\"in\":\"header\",\"required\":false,\"description\":\"Token\",\"schema\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"cookie_session_id\":{\"name\":\"session_id\",\"in\":\"cookie\",\"required\":true,\"schema\":{\"type\":\"string\"}") != null);
}

test "openapi deduplicates shared injected parameters into components" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-params-dedupe",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items-a/{item_id}", paramsHandler, .{});
    try app.get("/items-b/{item_id}", paramsHandler, .{});

    const doc = try app.openapi();
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(doc, "\"query_page\":{\"name\":\"page\""));
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(doc, "\"$ref\":\"#/components/parameters/query_page\""));
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
