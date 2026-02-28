const std = @import("std");
const zigmund = @import("zigmund");

fn echoHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "session middleware sets session cookie" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "session-test",
        .version = "0.0.1",
    });
    defer app.deinit();
    defer zigmund.mw.session.deinit();

    try app.addMiddleware(zigmund.sessionMw(std.testing.allocator, .{
        .cookie_name = "session_id",
        .max_age = 3600,
    }));
    try app.get("/page", echoHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/page");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);

    // Should have Set-Cookie with session ID
    var has_session_cookie = false;
    for (response.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "set-cookie")) {
            if (std.mem.indexOf(u8, h.value, "session_id=") != null) {
                has_session_cookie = true;
                // Verify cookie attributes
                try std.testing.expect(std.mem.indexOf(u8, h.value, "HttpOnly") != null);
                try std.testing.expect(std.mem.indexOf(u8, h.value, "SameSite=Lax") != null);
                try std.testing.expect(std.mem.indexOf(u8, h.value, "Max-Age=3600") != null);
            }
        }
    }
    try std.testing.expect(has_session_cookie);
}

test "session middleware generates unique session IDs" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "session-unique-test",
        .version = "0.0.1",
    });
    defer app.deinit();
    defer zigmund.mw.session.deinit();

    try app.addMiddleware(zigmund.sessionMw(std.testing.allocator, .{}));
    try app.get("/page", echoHandler, .{});

    // Use separate clients so cookies are not shared between requests
    var client1 = zigmund.TestClient.init(std.testing.allocator, &app);
    var client2 = zigmund.TestClient.init(std.testing.allocator, &app);

    // Get two sessions from separate clients (no cookie sharing)
    var resp1 = try client1.get("/page");
    defer resp1.deinit(std.testing.allocator);

    var resp2 = try client2.get("/page");
    defer resp2.deinit(std.testing.allocator);

    // Extract session IDs
    var id1: ?[]const u8 = null;
    var id2: ?[]const u8 = null;

    for (resp1.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "set-cookie")) {
            if (std.mem.indexOf(u8, h.value, "session_id=")) |start| {
                const val_start = start + "session_id=".len;
                const val_end = std.mem.indexOfScalarPos(u8, h.value, val_start, ';') orelse h.value.len;
                id1 = h.value[val_start..val_end];
            }
        }
    }
    for (resp2.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "set-cookie")) {
            if (std.mem.indexOf(u8, h.value, "session_id=")) |start| {
                const val_start = start + "session_id=".len;
                const val_end = std.mem.indexOfScalarPos(u8, h.value, val_start, ';') orelse h.value.len;
                id2 = h.value[val_start..val_end];
            }
        }
    }

    try std.testing.expect(id1 != null);
    try std.testing.expect(id2 != null);
    // Sessions should be different (both are new requests without cookies)
    try std.testing.expect(!std.mem.eql(u8, id1.?, id2.?));
}
