const std = @import("std");
const zigmund = @import("zigmund");

fn echoHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "CSRF middleware generates token cookie on GET" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "csrf-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.csrfMw(.{}));
    try app.get("/page", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/page");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // Should have Set-Cookie with CSRF token
    var has_csrf_cookie = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "set-cookie")) {
            if (std.mem.indexOf(u8, h.value, "_csrf_token=") != null) {
                has_csrf_cookie = true;
            }
        }
    }
    try std.testing.expect(has_csrf_cookie);
}

test "CSRF middleware rejects POST without token" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "csrf-reject-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.csrfMw(.{}));
    try app.post("/submit", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.post("/submit", "{}");
    defer response.deinit(std.testing.allocator);

    // Should be rejected with 403
    try std.testing.expectEqual(.forbidden, response.status);
}

test "CSRF middleware allows GET without token" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "csrf-get-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.csrfMw(.{}));
    try app.get("/page", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/page");
    defer response.deinit(std.testing.allocator);

    // GET should always be allowed (safe method)
    try std.testing.expectEqual(.ok, response.status);
}
