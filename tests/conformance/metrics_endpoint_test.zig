const std = @import("std");
const zigmund = @import("zigmund");

fn okHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("ok");
}

fn failHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return error.Outage;
}

test "metrics endpoint exposes prometheus counters and latency aggregates" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "metrics",
        .version = "0.0.1",
        .metrics_url = "/metrics",
    });
    defer app.deinit();

    try app.get("/ok", okHandler, .{});
    try app.get("/fail", failHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var ok1 = try client.get("/ok");
    defer ok1.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok1.status);

    var ok2 = try client.get("/ok");
    defer ok2.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok2.status);

    var fail = try client.get("/fail");
    defer fail.deinit(std.testing.allocator);
    try std.testing.expectEqual(.internal_server_error, fail.status);

    var metrics = try client.get("/metrics");
    defer metrics.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, metrics.status);
    try std.testing.expectEqualStrings("text/plain; version=0.0.4; charset=utf-8", metrics.content_type);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics.body,
        "zigmund_http_requests_total{method=\"GET\",path=\"/ok\",status=\"200\"} 2",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics.body,
        "zigmund_http_requests_total{method=\"GET\",path=\"/fail\",status=\"500\"} 1",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics.body,
        "zigmund_http_request_latency_us_count{method=\"GET\",path=\"/ok\",status=\"200\"} 2",
    ) != null);
}

test "metrics endpoint is disabled by default" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "metrics-disabled",
        .version = "0.0.1",
    });
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/metrics");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_found, res.status);
}

test "metrics endpoint supports custom path" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "metrics-custom",
        .version = "0.0.1",
        .metrics_url = "/internal/metrics",
    });
    defer app.deinit();

    try app.get("/ok", okHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var ok = try client.get("/ok");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);

    var custom = try client.get("/internal/metrics");
    defer custom.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, custom.status);
    try std.testing.expect(std.mem.indexOf(
        u8,
        custom.body,
        "zigmund_http_requests_total{method=\"GET\",path=\"/ok\",status=\"200\"} 1",
    ) != null);

    var missing = try client.get("/metrics");
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_found, missing.status);
}

test "metrics endpoint aggregates parameterized route metrics by template path" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "metrics-template-path",
        .version = "0.0.1",
        .metrics_url = "/metrics",
    });
    defer app.deinit();

    try app.get("/items/{item_id}", okHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var first = try client.get("/items/42");
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, first.status);

    var second = try client.get("/items/999");
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, second.status);

    var metrics = try client.get("/metrics");
    defer metrics.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, metrics.status);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics.body,
        "zigmund_http_requests_total{method=\"GET\",path=\"/items/{item_id}\",status=\"200\"} 2",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics.body,
        "zigmund_http_request_latency_us_count{method=\"GET\",path=\"/items/{item_id}\",status=\"200\"} 2",
    ) != null);
}

test "json sink adapters can be enabled directly on app" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "json-sinks",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.enableJsonTelemetrySink();
    app.enableJsonAccessLogSink();
    app.enableJsonMetricsSink();

    try app.get("/ok", okHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/ok");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);
}
