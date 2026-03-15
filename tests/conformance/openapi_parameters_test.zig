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

fn richParamHandler(
    next: zigmund.Query(std.Uri, .{ .alias = "next", .description = "Next page URI" }),
    ip: zigmund.Query(std.net.Ip4Address, .{ .alias = "ip", .description = "Client IPv4" }),
    peer: zigmund.Query(std.net.Ip6Address, .{ .alias = "peer", .description = "Peer IPv6" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .has_next = next.value != null,
        .has_ip = ip.value != null,
        .has_peer = peer.value != null,
    });
}

const QueryModel = struct {
    page: u32 = 1,
    search: ?[]const u8 = null,
    tags: []const []const u8,
};

const HeaderModel = struct {
    x_token: []const u8,
    save_data: ?[]const u8 = null,
};

const CookieModel = struct {
    session_id: []const u8,
    theme: ?[]const u8 = null,
};

fn modelParamHandler(
    query: zigmund.Query(QueryModel, .{}),
    headers: zigmund.Header(HeaderModel, .{}),
    cookies: zigmund.Cookie(CookieModel, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .has_query = query.value != null,
        .has_headers = headers.value != null,
        .has_cookies = cookies.value != null,
    });
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

test "openapi emits schema formats for uri and ip parameters" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-rich-params",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/resolve", richParamHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_next\":{\"name\":\"next\",\"in\":\"query\",\"required\":true,\"description\":\"Next page URI\",\"schema\":{\"type\":\"string\",\"format\":\"uri\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_ip\":{\"name\":\"ip\",\"in\":\"query\",\"required\":true,\"description\":\"Client IPv4\",\"schema\":{\"type\":\"string\",\"format\":\"ipv4\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_peer\":{\"name\":\"peer\",\"in\":\"query\",\"required\":true,\"description\":\"Peer IPv6\",\"schema\":{\"type\":\"string\",\"format\":\"ipv6\"}") != null);
}

test "openapi expands query header and cookie parameter models into flat parameters" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-param-models",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/models", modelParamHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_page\":{\"name\":\"page\",\"in\":\"query\",\"required\":false,\"schema\":{\"type\":\"integer\",\"format\":\"int32\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_search\":{\"name\":\"search\",\"in\":\"query\",\"required\":false,\"schema\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"query_tags\":{\"name\":\"tags\",\"in\":\"query\",\"required\":true,\"schema\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"header_x_token\":{\"name\":\"x-token\",\"in\":\"header\",\"required\":true,\"schema\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"header_save_data\":{\"name\":\"save-data\",\"in\":\"header\",\"required\":false,\"schema\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"cookie_session_id\":{\"name\":\"session_id\",\"in\":\"cookie\",\"required\":true,\"schema\":{\"type\":\"string\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"cookie_theme\":{\"name\":\"theme\",\"in\":\"cookie\",\"required\":false,\"schema\":{\"type\":\"string\"}") != null);
}
