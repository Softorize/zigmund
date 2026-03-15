const std = @import("std");
const zigmund = @import("zigmund");

fn fastHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "timeout middleware passes through fast requests" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "timeout-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.timeoutMw(std.testing.allocator, .{
        .timeout_ms = 5000,
    }));
    try app.get("/api/data", fastHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.get("/api/data");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
}

test "timeout config defaults are correct" {
    const config = zigmund.TimeoutConfig{};
    try std.testing.expectEqual(@as(u64, 30000), config.timeout_ms);
    try std.testing.expectEqualStrings("Request timeout", config.message);
}

test "timeout config accepts custom values" {
    const config = zigmund.TimeoutConfig{
        .timeout_ms = 5000,
        .message = "Too slow",
    };
    try std.testing.expectEqual(@as(u64, 5000), config.timeout_ms);
    try std.testing.expectEqualStrings("Too slow", config.message);
}

test "timeout middleware records start timestamp via dependency" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "timeout-stamp-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.timeoutMw(std.testing.allocator, .{
        .timeout_ms = 30000,
    }));
    try app.get("/api/data", fastHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // A normal fast request should succeed; the middleware sets the start
    // timestamp and checks elapsed time in the response hook. Since the
    // handler is fast, the response must be 200 OK.
    var response = try client.get("/api/data");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
}

test "timeout middleware state is isolated per app" {
    var app_one = try zigmund.App.init(std.testing.allocator, .{
        .title = "timeout-app-one",
        .version = "0.0.1",
    });
    defer app_one.deinit();
    try app_one.addMiddleware(zigmund.timeoutMw(std.testing.allocator, .{
        .timeout_ms = 5000,
    }));
    try app_one.get("/api/data", fastHandler, .{});

    var app_two = try zigmund.App.init(std.testing.allocator, .{
        .title = "timeout-app-two",
        .version = "0.0.1",
    });
    defer app_two.deinit();
    try app_two.addMiddleware(zigmund.timeoutMw(std.testing.allocator, .{
        .timeout_ms = 10000,
    }));
    try app_two.get("/api/data", fastHandler, .{});

    var client_one = zigmund.TestClient.init(std.testing.allocator, &app_one);
    defer client_one.deinit();
    var resp_one = try client_one.get("/api/data");
    defer resp_one.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, resp_one.status);

    var client_two = zigmund.TestClient.init(std.testing.allocator, &app_two);
    defer client_two.deinit();
    var resp_two = try client_two.get("/api/data");
    defer resp_two.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, resp_two.status);
}
