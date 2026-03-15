const std = @import("std");
const zigmund = @import("zigmund");

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

const AliasEntry = struct {
    field: []const u8,
    alias: []const u8,
};

const AliasedQueryModel = struct {
    page_size: u32 = 25,

    pub const zigmund_query_aliases: []const AliasEntry = &.{
        .{ .field = "page_size", .alias = "page-size" },
    };
};

const AliasedHeaderModel = struct {
    tenant_id: []const u8,

    pub const zigmund_header_aliases: []const AliasEntry = &.{
        .{ .field = "tenant_id", .alias = "x-tenant-id" },
    };
};

const AliasedCookieModel = struct {
    session_token: []const u8,

    pub const zigmund_cookie_aliases: []const AliasEntry = &.{
        .{ .field = "session_token", .alias = "session-token" },
    };
};

fn modelHandler(
    query: zigmund.Query(QueryModel, .{}),
    headers: zigmund.Header(HeaderModel, .{}),
    cookies: zigmund.Cookie(CookieModel, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = query.value.?.page,
        .search = query.value.?.search,
        .tags = query.value.?.tags,
        .token = headers.value.?.x_token,
        .save_data = headers.value.?.save_data,
        .session_id = cookies.value.?.session_id,
        .theme = cookies.value.?.theme,
    });
}

fn aliasedModelHandler(
    query: zigmund.Query(AliasedQueryModel, .{}),
    headers: zigmund.Header(AliasedHeaderModel, .{}),
    cookies: zigmund.Cookie(AliasedCookieModel, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page_size = query.value.?.page_size,
        .tenant_id = headers.value.?.tenant_id,
        .session_token = cookies.value.?.session_token,
    });
}

test "query header and cookie parameter models bind flat structs" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "param-models",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items", modelHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-token", .value = "abc123" },
        .{ .name = "save-data", .value = "enabled" },
        .{ .name = "cookie", .value = "session_id=s-1; theme=dark" },
    };

    var ok = try client.requestWithHeaders(
        .GET,
        "/items?page=2&search=zig&tags=api&tags=zig",
        "",
        &headers,
    );
    defer ok.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"page\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"search\":\"zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"tags\":[\"api\",\"zig\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"token\":\"abc123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"save_data\":\"enabled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"session_id\":\"s-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"theme\":\"dark\"") != null);

    var missing = try client.requestWithHeaders(
        .GET,
        "/items?page=2",
        "",
        &headers,
    );
    defer missing.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, missing.status);
    try std.testing.expect(std.mem.indexOf(u8, missing.body, "\"loc\":[\"query\",\"tags\"]") != null);
}

test "parameter model aliases bind runtime values and appear in openapi" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "param-model-aliases",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/aliased", aliasedModelHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-tenant-id", .value = "tenant-7" },
        .{ .name = "cookie", .value = "session-token=s-77" },
    };

    var res = try client.requestWithHeaders(
        .GET,
        "/aliased?page-size=50",
        "",
        &headers,
    );
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"page_size\":50") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"tenant_id\":\"tenant-7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"session_token\":\"s-77\"") != null);

    const openapi = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, openapi, "\"name\":\"page-size\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, openapi, "\"name\":\"x-tenant-id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, openapi, "\"name\":\"session-token\"") != null);
}
