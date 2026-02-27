const std = @import("std");
const zigmund = @import("zigmund");

fn flatten(comptime T: type, value: ?T) T {
    return value orelse null;
}

fn queryOptionalHandler(
    q: zigmund.Query([]const u8, .{ .alias = "q", .required = false }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .q = q.value,
    });
}

fn queryRequiredOptionalTypeHandler(
    q: zigmund.Query(?u8, .{ .alias = "q", .required = true }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .q = flatten(?u8, q.value),
    });
}

fn optionalHeaderCookieHandler(
    token: zigmund.Header(?[]const u8, .{ .alias = "x-token" }),
    session: zigmund.Cookie(?[]const u8, .{ .alias = "sid" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .token = flatten(?[]const u8, token.value),
        .session = flatten(?[]const u8, session.value),
    });
}

test "query required=false allows missing for non-optional value type" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "optional-query",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/search", queryOptionalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var missing = try client.get("/search");
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, missing.status);
    try std.testing.expect(std.mem.indexOf(u8, missing.body, "\"q\":null") != null);

    var present = try client.get("/search?q=zig");
    defer present.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, present.status);
    try std.testing.expect(std.mem.indexOf(u8, present.body, "\"q\":\"zig\"") != null);
}

test "query required=true rejects missing even when marker value type is optional" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "required-optional-query",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items", queryRequiredOptionalTypeHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var missing = try client.get("/items");
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, missing.status);
    try std.testing.expect(std.mem.indexOf(u8, missing.body, "\"loc\":[\"query\",\"q\"]") != null);

    var present = try client.get("/items?q=9");
    defer present.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, present.status);
    try std.testing.expect(std.mem.indexOf(u8, present.body, "\"q\":9") != null);
}

test "optional header and cookie markers do not fail when missing" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "optional-header-cookie",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/whoami", optionalHeaderCookieHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var missing = try client.get("/whoami");
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, missing.status);
    try std.testing.expect(std.mem.indexOf(u8, missing.body, "\"token\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, missing.body, "\"session\":null") != null);

    var present = try client.requestWithHeaders(.GET, "/whoami", "", &.{
        .{ .name = "x-token", .value = "abc" },
        .{ .name = "cookie", .value = "sid=s-1" },
    });
    defer present.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, present.status);
    try std.testing.expect(std.mem.indexOf(u8, present.body, "\"token\":\"abc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, present.body, "\"session\":\"s-1\"") != null);
}
