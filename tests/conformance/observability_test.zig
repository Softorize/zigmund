const std = @import("std");
const zigmund = @import("zigmund");

var telemetry_event_count: usize = 0;
var telemetry_last_status: ?std.http.Status = null;
var telemetry_last_latency_us: u64 = 0;
var telemetry_last_path: ?[]u8 = null;
var telemetry_last_request_id: ?[]u8 = null;
var access_log_event_count: usize = 0;
var access_log_last_trace_context: ?[]u8 = null;
var access_log_last_user_agent: ?[]u8 = null;
var metrics_event_count: usize = 0;
var metrics_last_name: ?[]u8 = null;
var metrics_last_value: f64 = 0;

fn resetTelemetryState(allocator: std.mem.Allocator) void {
    telemetry_event_count = 0;
    telemetry_last_status = null;
    telemetry_last_latency_us = 0;

    if (telemetry_last_path) |path| allocator.free(path);
    telemetry_last_path = null;

    if (telemetry_last_request_id) |request_id| allocator.free(request_id);
    telemetry_last_request_id = null;

    access_log_event_count = 0;
    if (access_log_last_trace_context) |trace_context| allocator.free(trace_context);
    access_log_last_trace_context = null;
    if (access_log_last_user_agent) |user_agent| allocator.free(user_agent);
    access_log_last_user_agent = null;

    metrics_event_count = 0;
    if (metrics_last_name) |name| allocator.free(name);
    metrics_last_name = null;
    metrics_last_value = 0;
}

fn telemetrySink(event: zigmund.App.TelemetryEvent, allocator: std.mem.Allocator) !void {
    if (telemetry_last_path) |path| allocator.free(path);
    if (telemetry_last_request_id) |request_id| allocator.free(request_id);

    telemetry_last_path = try allocator.dupe(u8, event.path);
    telemetry_last_request_id = try allocator.dupe(u8, event.request_id);
    telemetry_last_status = event.status;
    telemetry_last_latency_us = event.latency_us;
    telemetry_event_count += 1;
}

fn accessLogSink(event: zigmund.App.AccessLogEvent, allocator: std.mem.Allocator) !void {
    if (access_log_last_trace_context) |trace_context| allocator.free(trace_context);
    if (access_log_last_user_agent) |user_agent| allocator.free(user_agent);

    access_log_last_trace_context = try allocator.dupe(u8, event.trace_context);
    access_log_last_user_agent = try allocator.dupe(u8, event.user_agent);
    access_log_event_count += 1;
}

fn metricsSink(event: zigmund.App.MetricsEvent, allocator: std.mem.Allocator) !void {
    if (metrics_last_name) |name| allocator.free(name);
    metrics_last_name = try allocator.dupe(u8, event.name);
    metrics_last_value = event.value;
    metrics_event_count += 1;
}

fn observabilityHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .request_id = req.dependency("request_id") orelse "",
        .trace_context = req.dependency("trace_context") orelse "",
    });
}

test "request id trace context telemetry access logs and metrics are propagated" {
    resetTelemetryState(std.testing.allocator);
    defer resetTelemetryState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "observability",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setTelemetrySink(telemetrySink);
    app.setAccessLogSink(accessLogSink);
    app.setMetricsSink(metricsSink);
    try app.setTraceContextHeader("x-trace-id");
    try app.get("/observe", observabilityHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var generated = try client.get("/observe");
    defer generated.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, generated.status);
    const generated_request_id = generated.header("x-request-id") orelse return error.TestUnexpectedResult;
    try std.testing.expect(generated_request_id.len != 0);
    try std.testing.expect(std.mem.indexOf(u8, generated.body, generated_request_id) != null);

    try std.testing.expectEqual(@as(usize, 1), telemetry_event_count);
    try std.testing.expectEqual(.ok, telemetry_last_status.?);
    try std.testing.expectEqualStrings("/observe", telemetry_last_path.?);
    try std.testing.expectEqualStrings(generated_request_id, telemetry_last_request_id.?);
    try std.testing.expect(telemetry_last_latency_us >= 0);
    try std.testing.expectEqual(@as(usize, 1), access_log_event_count);
    try std.testing.expectEqualStrings("", access_log_last_trace_context.?);
    try std.testing.expectEqual(@as(usize, 2), metrics_event_count);
    try std.testing.expect(std.mem.eql(u8, metrics_last_name.?, "zigmund_http_request_latency_us"));
    try std.testing.expect(metrics_last_value >= 0);

    const headers = [_]std.http.Header{
        .{ .name = "x-request-id", .value = "external-request-id-1" },
        .{ .name = "x-trace-id", .value = "trace-123" },
        .{ .name = "user-agent", .value = "zigmund-test" },
    };
    var forwarded = try client.requestWithHeaders(.GET, "/observe", "", &headers);
    defer forwarded.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, forwarded.status);
    try std.testing.expectEqualStrings("external-request-id-1", forwarded.header("x-request-id").?);
    try std.testing.expect(std.mem.indexOf(u8, forwarded.body, "\"request_id\":\"external-request-id-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, forwarded.body, "\"trace_context\":\"trace-123\"") != null);
    try std.testing.expectEqual(@as(usize, 2), telemetry_event_count);
    try std.testing.expectEqualStrings("external-request-id-1", telemetry_last_request_id.?);
    try std.testing.expectEqual(@as(usize, 2), access_log_event_count);
    try std.testing.expectEqualStrings("trace-123", access_log_last_trace_context.?);
    try std.testing.expectEqualStrings("zigmund-test", access_log_last_user_agent.?);
    try std.testing.expectEqual(@as(usize, 4), metrics_event_count);
}
