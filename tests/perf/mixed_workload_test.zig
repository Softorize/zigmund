const std = @import("std");
const zigmund = @import("zigmund");

fn health(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return .{
        .status = .ok,
        .body = "{\"ok\":true}",
        .content_type = "application/json",
    };
}

fn item(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return .{
        .status = .ok,
        .body = "{\"id\":\"42\",\"name\":\"perf-item\"}",
        .content_type = "application/json",
    };
}

fn search(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return .{
        .status = .ok,
        .body = "{\"term\":\"zig\",\"hits\":3}",
        .content_type = "application/json",
    };
}

fn submit(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return .{
        .status = .ok,
        .body = "{\"accepted\":true}",
        .content_type = "application/json",
    };
}

test "perf mixed workload: representative route mix throughput" {
    const perf_allocator = std.heap.page_allocator;

    var app = try zigmund.App.init(perf_allocator, .{
        .title = "perf-mixed",
        .version = "0.0.1",
        .openapi_url = null,
        .docs_url = null,
        .redoc_url = null,
        .request_id_enabled = false,
    });
    defer app.deinit();

    try app.get("/health", health, .{});
    try app.get("/items/{item_id}", item, .{});
    try app.get("/search", search, .{});
    try app.post("/submit", submit, .{});

    var client = zigmund.TestClient.init(perf_allocator, &app);
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
        defer res.deinit(perf_allocator);
        if (res.status != .ok) return error.UnexpectedStatus;
    }

    const elapsed_ns = timer.read();
    const throughput_rps = @as(f64, @floatFromInt(iterations)) /
        (@as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_s));

    std.debug.print(
        "PERF_MIXED iterations={d} throughput_rps={d:.2}\n",
        .{ iterations, throughput_rps },
    );
    try std.testing.expect(throughput_rps > 0);
}
