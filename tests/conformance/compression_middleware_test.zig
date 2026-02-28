const std = @import("std");
const zigmund = @import("zigmund");

fn largeHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    // Generate body > 1KB to trigger compression
    const body = try allocator.alloc(u8, 2048);
    @memset(body, 'A');
    return .{
        .status = .ok,
        .body = body,
        .content_type = "text/plain",
        .owned_body = body,
    };
}

fn smallHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "compression middleware compresses large text responses with gzip" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "compression-gzip-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.compressionMw(.{ .min_size = 1024 }));
    try app.get("/large", largeHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/large", "", &.{
        .{ .name = "accept-encoding", .value = "gzip" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // Verify Content-Encoding header is set
    var has_encoding = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-encoding")) {
            has_encoding = true;
            try std.testing.expectEqualStrings("gzip", h.value);
        }
    }
    try std.testing.expect(has_encoding);

    // Compressed body should be significantly smaller than 2048
    try std.testing.expect(response.body.len < 2048);
    try std.testing.expect(response.body.len > 0);
}

test "compression middleware compresses large text responses with deflate" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "compression-deflate-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.compressionMw(.{ .min_size = 1024 }));
    try app.get("/large", largeHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/large", "", &.{
        .{ .name = "accept-encoding", .value = "deflate" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    var has_encoding = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-encoding")) {
            has_encoding = true;
            try std.testing.expectEqualStrings("deflate", h.value);
        }
    }
    try std.testing.expect(has_encoding);
    try std.testing.expect(response.body.len < 2048);
}

test "compression middleware skips small responses" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "compression-skip-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.compressionMw(.{ .min_size = 1024 }));
    try app.get("/small", smallHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/small", "", &.{
        .{ .name = "accept-encoding", .value = "gzip" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // No Content-Encoding header for small responses
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-encoding")) {
            return error.TestUnexpectedResult;
        }
    }
}

test "compression middleware skips when no accept-encoding" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "compression-no-accept-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.compressionMw(.{ .min_size = 1024 }));
    try app.get("/large", largeHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.get("/large");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // No Content-Encoding header
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-encoding")) {
            return error.TestUnexpectedResult;
        }
    }
}
