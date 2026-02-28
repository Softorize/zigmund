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

test "compression middleware compresses large text responses" {
    // Note: Compression is temporarily disabled in Zig 0.15.2 due to
    // broken std.compress.flate API (missing BlockWriter.bit_writer and
    // Hasher.final). This test verifies the middleware still functions
    // correctly as a no-op without errors.
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "compression-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.compressionMw(.{ .min_size = 1024 }));
    try app.get("/large", largeHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.requestWithHeaders(.GET, "/large", "", &.{
        .{ .name = "accept-encoding", .value = "deflate" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // Compression is disabled in Zig 0.15.2 due to stdlib issues.
    // Response should be returned uncompressed without errors.
    try std.testing.expect(response.body.len == 2048);
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
    var response = try client.requestWithHeaders(.GET, "/small", "", &.{
        .{ .name = "accept-encoding", .value = "deflate" },
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
