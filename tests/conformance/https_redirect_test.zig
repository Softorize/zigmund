const std = @import("std");
const zigmund = @import("zigmund");

fn echoHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "HTTPS redirect passes through when X-Forwarded-Proto is https" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "https-redirect-passthrough",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.httpsRedirectMw(std.testing.allocator, .{}));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "host", .value = "example.com" },
        .{ .name = "x-forwarded-proto", .value = "https" },
    });
    defer response.deinit(std.testing.allocator);

    // Should pass through with no redirect.
    try std.testing.expectEqual(.ok, response.status);
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "location")) {
            return error.TestUnexpectedResult;
        }
    }
}

test "HTTPS redirect returns 307 when request is HTTP" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "https-redirect-http",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.httpsRedirectMw(std.testing.allocator, .{}));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/api/data?foo=bar", "", &.{
        .{ .name = "host", .value = "example.com" },
        .{ .name = "x-forwarded-proto", .value = "http" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.temporary_redirect, response.status);

    var location: ?[]const u8 = null;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "location")) {
            location = h.value;
        }
    }
    try std.testing.expect(location != null);
    try std.testing.expectEqualStrings("https://example.com/api/data?foo=bar", location.?);
}

test "HTTPS redirect uses custom status code" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "https-redirect-301",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.httpsRedirectMw(std.testing.allocator, .{
        .redirect_status = .moved_permanently,
    }));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "host", .value = "example.com" },
        .{ .name = "x-forwarded-proto", .value = "http" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.moved_permanently, response.status);
}

test "HTTPS redirect uses custom port" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "https-redirect-port",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.httpsRedirectMw(std.testing.allocator, .{
        .https_port = 8443,
    }));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "host", .value = "example.com:8080" },
        .{ .name = "x-forwarded-proto", .value = "http" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.temporary_redirect, response.status);

    var location: ?[]const u8 = null;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "location")) {
            location = h.value;
        }
    }
    try std.testing.expect(location != null);
    try std.testing.expectEqualStrings("https://example.com:8443/api/data", location.?);
}

test "HTTPS redirect config defaults are correct" {
    const config = zigmund.HttpsRedirectConfig{};
    try std.testing.expectEqual(.temporary_redirect, config.redirect_status);
    try std.testing.expectEqual(@as(?u16, null), config.https_port);
}

test "HTTPS redirect without host header does not redirect" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "https-redirect-no-host",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.httpsRedirectMw(std.testing.allocator, .{}));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    // No host header, no x-forwarded-proto - should pass through.
    var response = try client.get("/api/data");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
}
