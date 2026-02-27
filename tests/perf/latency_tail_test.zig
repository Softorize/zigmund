const std = @import("std");
const zigmund = @import("zigmund");

fn delayed(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    if (std.mem.eql(u8, req.queryParam("slow") orelse "", "1")) {
        std.Thread.sleep(250 * std.time.ns_per_us);
    }
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn percentile(values: []u64, p: f64) u64 {
    if (values.len == 0) return 0;
    const clamped = @max(@as(f64, 0), @min(@as(f64, 1), p));
    const idx_f = clamped * @as(f64, @floatFromInt(values.len - 1));
    const idx: usize = @intFromFloat(idx_f);
    return values[idx];
}

test "perf latency tail: p95/p99 for mixed normal and slow requests" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "perf-tail",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/work", delayed, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    const iterations: usize = 2_000;
    var latencies_us = try std.testing.allocator.alloc(u64, iterations);
    defer std.testing.allocator.free(latencies_us);

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const path = if (i % 10 == 0) "/work?slow=1" else "/work";
        var timer = try std.time.Timer.start();
        var res = try client.get(path);
        defer res.deinit(std.testing.allocator);
        try std.testing.expectEqual(.ok, res.status);
        latencies_us[i] = timer.read() / std.time.ns_per_us;
    }

    std.mem.sort(u64, latencies_us, {}, std.sort.asc(u64));
    const p95 = percentile(latencies_us, 0.95);
    const p99 = percentile(latencies_us, 0.99);

    std.log.info(
        "perf_tail iterations={d} p95_us={d} p99_us={d}",
        .{ iterations, p95, p99 },
    );
    try std.testing.expect(p95 > 0);
    try std.testing.expect(p99 >= p95);
}
