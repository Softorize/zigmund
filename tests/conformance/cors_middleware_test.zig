const std = @import("std");
const zigmund = @import("zigmund");

fn echoHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "CORS middleware adds headers for allowed origin" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "cors-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.corsMw(.{
        .allowed_origins = &.{"https://example.com"},
    }));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.requestWithHeaders(.GET, "/api/data", "", &.{
        .{ .name = "origin", .value = "https://example.com" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // Check CORS headers
    var has_allow_origin = false;
    var has_vary = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "access-control-allow-origin")) {
            has_allow_origin = true;
            try std.testing.expectEqualStrings("https://example.com", h.value);
        }
        if (std.ascii.eqlIgnoreCase(h.name, "vary")) {
            has_vary = true;
        }
    }
    try std.testing.expect(has_allow_origin);
    try std.testing.expect(has_vary);
}

test "CORS middleware returns 204 for preflight OPTIONS" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "cors-preflight-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.corsMw(.{
        .allowed_origins = &.{"*"},
    }));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.requestWithHeaders(.OPTIONS, "/api/data", "", &.{
        .{ .name = "origin", .value = "https://app.example.com" },
        .{ .name = "access-control-request-method", .value = "POST" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.no_content, response.status);

    // Check preflight-specific headers
    var has_allow_methods = false;
    var has_allow_headers = false;
    var has_max_age = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "access-control-allow-methods")) has_allow_methods = true;
        if (std.ascii.eqlIgnoreCase(h.name, "access-control-allow-headers")) has_allow_headers = true;
        if (std.ascii.eqlIgnoreCase(h.name, "access-control-max-age")) has_max_age = true;
    }
    try std.testing.expect(has_allow_methods);
    try std.testing.expect(has_allow_headers);
    try std.testing.expect(has_max_age);
}

test "CORS middleware ignores requests without Origin header" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "cors-no-origin-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.corsMw(.{}));
    try app.get("/api/data", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/api/data");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // No CORS headers should be present
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "access-control-allow-origin")) {
            return error.TestUnexpectedResult;
        }
    }
}
