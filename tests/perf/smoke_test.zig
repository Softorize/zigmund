const std = @import("std");
const zigmund = @import("zigmund");

fn health(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "dispatch smoke throughput baseline" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "perf",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/health", health, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var res = try client.get("/health");
        defer res.deinit(std.testing.allocator);
        try std.testing.expectEqual(.ok, res.status);
    }
    const ns = timer.read();
    try std.testing.expect(ns > 0);
}
