const std = @import("std");
const zigmund = @import("zigmund");

fn alwaysOk() !void {}

fn alwaysFail() !void {
    return error.ConnectionRefused;
}

test "liveness endpoint always returns 200 with alive status" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "health-live-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.enableHealthEndpoints();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var response = try client.get("/health/live");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"status\":\"alive\"") != null);
}

test "readiness endpoint returns 200 when all checks pass" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "health-ready-ok-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.enableHealthEndpoints();
    try app.addHealthCheck("db", alwaysOk);
    try app.addHealthCheck("cache", alwaysOk);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var response = try client.get("/health/ready");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"status\":\"healthy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"db\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"cache\":\"ok\"") != null);
}

test "readiness endpoint returns 503 when a check fails" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "health-ready-fail-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.enableHealthEndpoints();
    try app.addHealthCheck("db", alwaysOk);
    try app.addHealthCheck("cache", alwaysFail);

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var response = try client.get("/health/ready");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.service_unavailable, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"status\":\"unhealthy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"db\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"cache\":\"failed: ConnectionRefused\"") != null);
}

test "readiness endpoint returns healthy with empty checks" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "health-ready-empty-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.enableHealthEndpoints();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var response = try client.get("/health/ready");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"status\":\"healthy\"") != null);
}

test "health endpoints return 404 when not enabled" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "health-disabled-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var live = try client.get("/health/live");
    defer live.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_found, live.status);

    var ready = try client.get("/health/ready");
    defer ready.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_found, ready.status);
}
