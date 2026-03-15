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
