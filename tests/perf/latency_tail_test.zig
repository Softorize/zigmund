const std = @import("std");
const zigmund = @import("zigmund");

fn delayed(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    if (std.mem.eql(u8, req.queryParam("slow") orelse "", "1")) {
        const delay_ns: u64 = 150 * std.time.ns_per_us;
        var timer = try std.time.Timer.start();
        while (timer.read() < delay_ns) {
            std.atomic.spinLoopHint();
        }
    }
    _ = allocator;
    return .{
        .status = .ok,
        .body = "{\"ok\":true}",
        .content_type = "application/json",
    };
}

fn percentile(values: []u64, p: f64) u64 {
    if (values.len == 0) return 0;
    const clamped = @max(@as(f64, 0), @min(@as(f64, 1), p));
    const idx_f = clamped * @as(f64, @floatFromInt(values.len - 1));
    const idx: usize = @intFromFloat(idx_f);
    return values[idx];
}

test "perf latency tail: p95/p99 for mixed normal and slow requests" {
    const perf_allocator = std.heap.page_allocator;

    var app = try zigmund.App.init(perf_allocator, .{
        .title = "perf-tail",
        .version = "0.0.1",
        .openapi_url = null,
        .docs_url = null,
        .redoc_url = null,
        .request_id_enabled = false,
    });
    defer app.deinit();

    try app.get("/work", delayed, .{});

    var client = zigmund.TestClient.init(perf_allocator, &app);
    const iterations: usize = 2_000;
    var latencies_us = try perf_allocator.alloc(u64, iterations);
    defer perf_allocator.free(latencies_us);

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const path = if (i % 20 == 0) "/work?slow=1" else "/work";
        var timer = try std.time.Timer.start();
        var res = try client.get(path);
        defer res.deinit(perf_allocator);
        if (res.status != .ok) return error.UnexpectedStatus;
        latencies_us[i] = timer.read() / std.time.ns_per_us;
    }

    std.mem.sort(u64, latencies_us, {}, std.sort.asc(u64));
    const p95 = percentile(latencies_us, 0.95);
    const p99 = percentile(latencies_us, 0.99);

    std.debug.print(
        "PERF_TAIL iterations={d} p95_us={d} p99_us={d}\n",
        .{ iterations, p95, p99 },
    );
    try std.testing.expect(p95 > 0);
    try std.testing.expect(p99 >= p95);
}
