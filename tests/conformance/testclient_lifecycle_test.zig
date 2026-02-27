const std = @import("std");
const zigmund = @import("zigmund");

var startup_calls: usize = 0;
var shutdown_calls: usize = 0;

fn startupHook() !void {
    startup_calls += 1;
}

fn shutdownHook() !void {
    shutdown_calls += 1;
}

fn okHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("ok");
}

test "test client starts lifespan lazily and supports explicit close" {
    startup_calls = 0;
    shutdown_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "testclient-lifecycle",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.onStartup(startupHook);
    try app.onShutdown(shutdownHook);
    try app.get("/ok", okHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    try std.testing.expectEqual(@as(usize, 0), startup_calls);
    try std.testing.expectEqual(@as(usize, 0), shutdown_calls);

    var first = try client.get("/ok");
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, first.status);
    try std.testing.expectEqual(@as(usize, 1), startup_calls);
    try std.testing.expectEqual(@as(usize, 0), shutdown_calls);

    var second = try client.get("/ok");
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, second.status);
    try std.testing.expectEqual(@as(usize, 1), startup_calls);

    try client.close();
    try std.testing.expectEqual(@as(usize, 1), shutdown_calls);

    try client.close();
    try std.testing.expectEqual(@as(usize, 1), shutdown_calls);

    var third = try client.get("/ok");
    defer third.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, third.status);
    try std.testing.expectEqual(@as(usize, 2), startup_calls);
}

test "test client deinit closes lifespan automatically after requests" {
    startup_calls = 0;
    shutdown_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "testclient-lifecycle-deinit",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.onStartup(startupHook);
    try app.onShutdown(shutdownHook);
    try app.get("/ok", okHandler, .{});

    {
        var client = zigmund.TestClient.init(std.testing.allocator, &app);
        var res = try client.get("/ok");
        defer res.deinit(std.testing.allocator);
        try std.testing.expectEqual(.ok, res.status);
        client.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), startup_calls);
    try std.testing.expectEqual(@as(usize, 1), shutdown_calls);
}
