const std = @import("std");
const zigmund = @import("zigmund");

fn echoHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "rate limit middleware adds X-RateLimit headers" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "rate-limit-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.rateLimitMw(std.testing.allocator, .{
        .max_requests = 10,
        .window_seconds = 60,
    }));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "x-forwarded-for", .value = "10.0.0.1" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // Check rate limit headers
    var has_limit = false;
    var has_remaining = false;
    var has_reset = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "x-ratelimit-limit")) {
            has_limit = true;
            try std.testing.expectEqualStrings("10", h.value);
        }
        if (std.ascii.eqlIgnoreCase(h.name, "x-ratelimit-remaining")) has_remaining = true;
        if (std.ascii.eqlIgnoreCase(h.name, "x-ratelimit-reset")) has_reset = true;
    }
    try std.testing.expect(has_limit);
    try std.testing.expect(has_remaining);
    try std.testing.expect(has_reset);
}

test "rate limit middleware state is isolated per app" {
    var app_one = try zigmund.App.init(std.testing.allocator, .{
        .title = "rate-limit-app-one",
        .version = "0.0.1",
    });
    defer app_one.deinit();
    try app_one.addMiddleware(zigmund.rateLimitMw(std.testing.allocator, .{
        .max_requests = 1,
        .window_seconds = 60,
    }));
    try app_one.get("/api/data", echoHandler, .{});

    var app_two = try zigmund.App.init(std.testing.allocator, .{
        .title = "rate-limit-app-two",
        .version = "0.0.1",
    });
    defer app_two.deinit();
    try app_two.addMiddleware(zigmund.rateLimitMw(std.testing.allocator, .{
        .max_requests = 1,
        .window_seconds = 60,
    }));
    try app_two.get("/api/data", echoHandler, .{});

    var client_one = zigmund.TestClient.init(std.testing.allocator, &app_one);
    defer client_one.deinit();
    var first = try client_one.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "x-forwarded-for", .value = "10.0.0.7" },
    });
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, first.status);

    var second = try client_one.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "x-forwarded-for", .value = "10.0.0.7" },
    });
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(.too_many_requests, second.status);

    var client_two = zigmund.TestClient.init(std.testing.allocator, &app_two);
    defer client_two.deinit();
    var isolated = try client_two.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "x-forwarded-for", .value = "10.0.0.7" },
    });
    defer isolated.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, isolated.status);
}
