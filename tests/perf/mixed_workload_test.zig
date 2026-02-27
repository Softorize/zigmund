const std = @import("std");
const zigmund = @import("zigmund");

fn health(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn item(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .id = req.param("item_id") orelse "0",
        .name = "perf-item",
    });
}

fn search(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .term = req.queryParam("q") orelse "",
        .hits = @as(u32, 3),
    });
}

fn submit(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const Payload = struct {
        message: []const u8,
    };
    const body = req.bodyJsonLeaky(Payload) catch Payload{ .message = "" };
    return zigmund.Response.json(allocator, .{
        .accepted = true,
        .message = body.message,
    });
}

test "perf mixed workload: representative route mix throughput" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "perf-mixed",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/health", health, .{});
    try app.get("/items/{item_id}", item, .{});
    try app.get("/search", search, .{});
    try app.post("/submit", submit, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    const iterations: usize = 6_000;

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const bucket = i % 10;
        var res = blk: {
            if (bucket < 4) break :blk try client.get("/health");
            if (bucket < 7) break :blk try client.get("/items/42");
            if (bucket < 9) break :blk try client.get("/search?q=zig");
            break :blk try client.post("/submit", "{\"message\":\"hello\"}");
        };
        defer res.deinit(std.testing.allocator);
        try std.testing.expectEqual(.ok, res.status);
    }

    const elapsed_ns = timer.read();
    const throughput_rps = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_s));

    std.log.info(
        "perf_mixed iterations={d} elapsed_ns={d} throughput_rps={d:.2}",
        .{ iterations, elapsed_ns, throughput_rps },
    );
    try std.testing.expect(throughput_rps > 0);
}
