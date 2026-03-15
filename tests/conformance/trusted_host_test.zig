const std = @import("std");
const zigmund = @import("zigmund");

fn echoHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "trusted host middleware allows matching host" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "trusted-host-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.trustedHostMw(std.testing.allocator, .{
        .allowed_hosts = &.{"example.com"},
    }));
    try app.get("/test", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "host", .value = "example.com" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
}

test "trusted host middleware rejects disallowed host with 400" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "trusted-host-reject-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.trustedHostMw(std.testing.allocator, .{
        .allowed_hosts = &.{"example.com"},
    }));
    try app.get("/test", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "host", .value = "evil.com" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.bad_request, response.status);
}

test "trusted host middleware wildcard allows everything" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "trusted-host-wildcard-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.trustedHostMw(std.testing.allocator, .{
        .allowed_hosts = &.{"*"},
    }));
    try app.get("/test", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "host", .value = "literally-anything.example.org" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
}

test "trusted host middleware subdomain wildcard matching" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "trusted-host-subdomain-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.trustedHostMw(std.testing.allocator, .{
        .allowed_hosts = &.{".example.com"},
    }));
    try app.get("/test", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // Subdomain should be allowed
    var r1 = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "host", .value = "api.example.com" },
    });
    defer r1.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, r1.status);

    // Bare domain should also be allowed
    var r2 = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "host", .value = "example.com" },
    });
    defer r2.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, r2.status);

    // Unrelated domain should be rejected
    var r3 = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "host", .value = "evil.com" },
    });
    defer r3.deinit(std.testing.allocator);
    try std.testing.expectEqual(.bad_request, r3.status);
}

test "trusted host middleware rejects missing host header by default" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "trusted-host-missing-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.trustedHostMw(std.testing.allocator, .{
        .allowed_hosts = &.{"example.com"},
        .allow_missing_host = false,
    }));
    try app.get("/test", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.get("/test");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.bad_request, response.status);
}

test "trusted host middleware allows missing host when configured" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "trusted-host-allow-missing-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.trustedHostMw(std.testing.allocator, .{
        .allowed_hosts = &.{"example.com"},
        .allow_missing_host = true,
    }));
    try app.get("/test", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.get("/test");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
}
