const std = @import("std");
const zigmund = @import("zigmund");

fn health(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

test "perf microbenchmark: single json endpoint throughput and mean latency" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "perf-micro",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/health", health, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    const iterations: usize = 5_000;

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var res = try client.get("/health");
        defer res.deinit(std.testing.allocator);
        try std.testing.expectEqual(.ok, res.status);
    }

    const elapsed_ns = timer.read();
    const throughput_rps = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_s));
    const mean_latency_us = (@as(f64, @floatFromInt(elapsed_ns)) /
        @as(f64, @floatFromInt(iterations))) / @as(f64, std.time.ns_per_us);

    std.debug.print(
        "PERF_MICRO iterations={d} throughput_rps={d:.2} mean_latency_us={d:.2}\n",
        .{ iterations, throughput_rps, mean_latency_us },
    );
    try std.testing.expect(throughput_rps > 0);
    try std.testing.expect(mean_latency_us > 0);
}
