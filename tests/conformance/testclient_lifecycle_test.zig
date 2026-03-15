const std = @import("std");
const zigmund = @import("zigmund");

var startup_calls: usize = 0;
var shutdown_calls: usize = 0;
var lifecycle_order: [8]u8 = undefined;
var lifecycle_order_len: usize = 0;

fn startupHook() !void {
    startup_calls += 1;
}

fn shutdownHook() !void {
    shutdown_calls += 1;
}

fn resetLifecycleOrder() void {
    lifecycle_order_len = 0;
}

fn pushLifecycle(ch: u8) void {
    lifecycle_order[lifecycle_order_len] = ch;
    lifecycle_order_len += 1;
}

fn startupA() !void {
    pushLifecycle('A');
}

fn shutdownA() !void {
    pushLifecycle('a');
}

fn startupB() !void {
    pushLifecycle('B');
}

fn shutdownB() !void {
    pushLifecycle('b');
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

test "lifespan registers paired hooks and shutdown runs in reverse order" {
    resetLifecycleOrder();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "testclient-lifespan-paired",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.lifespan(startupA, shutdownA);
    try app.lifespan(startupB, shutdownB);
    try app.get("/ok", okHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var res = try client.get("/ok");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);

    try client.close();

    try std.testing.expectEqualSlices(u8, "ABba", lifecycle_order[0..lifecycle_order_len]);
}
