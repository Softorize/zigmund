const std = @import("std");
const zigmund = @import("zigmund");

fn v1ItemsHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("items-v1");
}

fn v2ItemsHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("items-v2");
}

fn v1UsersHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("users-v1");
}

test "versioned routers serve different responses at /v1 and /v2 prefixes" {
    var v1 = zigmund.Router.init(std.testing.allocator);
    defer v1.deinit();
    try v1.addHttpRoute(.GET, "/items", v1ItemsHandler, .{});

    var v2 = zigmund.Router.init(std.testing.allocator);
    defer v2.deinit();
    try v2.addHttpRoute(.GET, "/items", v2ItemsHandler, .{});

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "api-versioning-test",
        .version = "1.0.0",
    });
    defer app.deinit();

    try zigmund.mountVersionedRouters(&app, .{}, &.{
        .{ .version = 1, .router = &v1 },
        .{ .version = 2, .router = &v2 },
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    // -- /v1/items returns v1 response --
    var resp1 = try client.get("/v1/items");
    defer resp1.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, resp1.status);
    try std.testing.expectEqualStrings("items-v1", resp1.body);

    // -- /v2/items returns v2 response --
    var resp2 = try client.get("/v2/items");
    defer resp2.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, resp2.status);
    try std.testing.expectEqualStrings("items-v2", resp2.body);
}

test "versioned routers with custom prefix" {
    var v3 = zigmund.Router.init(std.testing.allocator);
    defer v3.deinit();
    try v3.addHttpRoute(.GET, "/users", v1UsersHandler, .{});

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "custom-prefix-test",
        .version = "1.0.0",
    });
    defer app.deinit();

    try zigmund.mountVersionedRouters(&app, .{ .prefix = "/api/v" }, &.{
        .{ .version = 3, .router = &v3 },
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var resp = try client.get("/api/v3/users");
    defer resp.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, resp.status);
    try std.testing.expectEqualStrings("users-v1", resp.body);
}

test "versioned routers appear in OpenAPI spec under versioned paths" {
    var v1 = zigmund.Router.init(std.testing.allocator);
    defer v1.deinit();
    try v1.addHttpRoute(.GET, "/items", v1ItemsHandler, .{});

    var v2 = zigmund.Router.init(std.testing.allocator);
    defer v2.deinit();
    try v2.addHttpRoute(.GET, "/items", v2ItemsHandler, .{});

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-versioning-test",
        .version = "1.0.0",
    });
    defer app.deinit();

    try zigmund.mountVersionedRouters(&app, .{}, &.{
        .{ .version = 1, .router = &v1 },
        .{ .version = 2, .router = &v2 },
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/v1/items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/v2/items\"") != null);
}

test "versionFromHeader extracts version from Accept-Version header" {
    var req = try zigmund.Request.initSyntheticWithHeaders(
        std.testing.allocator,
        .GET,
        "/items",
        "",
        &.{.{ .name = "Accept-Version", .value = "2" }},
    );
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, 2), zigmund.versionFromHeader(&req));
}

test "versionFromHeader extracts version from X-API-Version header" {
    var req = try zigmund.Request.initSyntheticWithHeaders(
        std.testing.allocator,
        .GET,
        "/items",
        "",
        &.{.{ .name = "X-API-Version", .value = "7" }},
    );
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, 7), zigmund.versionFromHeader(&req));
}

test "versionFromHeader returns null without version header" {
    var req = try zigmund.Request.initSynthetic(std.testing.allocator, .GET, "/items", "");
    defer req.deinit();

    try std.testing.expectEqual(@as(?u32, null), zigmund.versionFromHeader(&req));
}

test "versioned routers forward include-router options (tags)" {
    var v1 = zigmund.Router.init(std.testing.allocator);
    defer v1.deinit();
    try v1.addHttpRoute(.GET, "/items", v1ItemsHandler, .{});

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "tags-test",
        .version = "1.0.0",
    });
    defer app.deinit();

    try zigmund.mountVersionedRouters(&app, .{}, &.{
        .{ .version = 1, .router = &v1, .options = .{ .tags = &.{"v1"} } },
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/v1/items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"v1\"") != null);
}
