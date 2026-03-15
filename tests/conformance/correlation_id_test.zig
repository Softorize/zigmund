const std = @import("std");
const zigmund = @import("zigmund");

var telemetry_last_correlation_id: ?[]u8 = null;
var trace_last_correlation_id: ?[]u8 = null;
var access_log_last_correlation_id: ?[]u8 = null;

fn resetState(allocator: std.mem.Allocator) void {
    if (telemetry_last_correlation_id) |id| allocator.free(id);
    telemetry_last_correlation_id = null;
    if (trace_last_correlation_id) |id| allocator.free(id);
    trace_last_correlation_id = null;
    if (access_log_last_correlation_id) |id| allocator.free(id);
    access_log_last_correlation_id = null;
}

fn telemetrySink(event: zigmund.App.TelemetryEvent, allocator: std.mem.Allocator) !void {
    if (telemetry_last_correlation_id) |id| allocator.free(id);
    telemetry_last_correlation_id = try allocator.dupe(u8, event.correlation_id);
}

fn traceSink(event: zigmund.App.TraceEvent, allocator: std.mem.Allocator) !void {
    if (trace_last_correlation_id) |id| allocator.free(id);
    trace_last_correlation_id = try allocator.dupe(u8, event.correlation_id);
}

fn accessLogSink(event: zigmund.App.AccessLogEvent, allocator: std.mem.Allocator) !void {
    if (access_log_last_correlation_id) |id| allocator.free(id);
    access_log_last_correlation_id = try allocator.dupe(u8, event.correlation_id);
}

fn correlationHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .correlation_id = req.dependency("correlation_id") orelse "",
        .request_id = req.dependency("request_id") orelse "",
    });
}

test "incoming x-correlation-id is preserved and returned in response" {
    resetState(std.testing.allocator);
    defer resetState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "correlation-id-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setTelemetrySink(telemetrySink);
    app.setTraceSink(traceSink);
    app.setAccessLogSink(accessLogSink);
    try app.get("/test", correlationHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "x-correlation-id", .value = "upstream-corr-abc-123" },
    });
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);

    // The correlation ID header should be returned in the response
    const response_corr_id = res.header("x-correlation-id") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("upstream-corr-abc-123", response_corr_id);

    // The correlation ID should be available as a dependency in the handler
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"correlation_id\":\"upstream-corr-abc-123\"") != null);

    // The correlation ID should be propagated to all observability events
    try std.testing.expectEqualStrings("upstream-corr-abc-123", telemetry_last_correlation_id.?);
    try std.testing.expectEqualStrings("upstream-corr-abc-123", trace_last_correlation_id.?);
    try std.testing.expectEqualStrings("upstream-corr-abc-123", access_log_last_correlation_id.?);
}

test "missing correlation id is auto-generated and returned in response" {
    resetState(std.testing.allocator);
    defer resetState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "correlation-id-auto-gen",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setTelemetrySink(telemetrySink);
    app.setTraceSink(traceSink);
    app.setAccessLogSink(accessLogSink);
    try app.get("/test", correlationHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    // No x-correlation-id header sent
    var res = try client.get("/test");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);

    // A correlation ID should still be generated and returned
    const response_corr_id = res.header("x-correlation-id") orelse return error.TestUnexpectedResult;
    try std.testing.expect(response_corr_id.len > 0);

    // It should be available as a dependency
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"correlation_id\":\"") != null);

    // It should match the request ID (fallback behavior)
    const response_req_id = res.header("x-request-id") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(response_req_id, response_corr_id);

    // It should be in telemetry events
    try std.testing.expectEqualStrings(response_corr_id, telemetry_last_correlation_id.?);
    try std.testing.expectEqualStrings(response_corr_id, trace_last_correlation_id.?);
    try std.testing.expectEqualStrings(response_corr_id, access_log_last_correlation_id.?);
}

test "correlation id is distinct from request id when both headers are present" {
    resetState(std.testing.allocator);
    defer resetState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "correlation-id-distinct",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setTelemetrySink(telemetrySink);
    try app.get("/test", correlationHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "x-request-id", .value = "req-external-1" },
        .{ .name = "x-correlation-id", .value = "corr-external-1" },
    });
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);

    // Both headers should be returned independently
    try std.testing.expectEqualStrings("req-external-1", res.header("x-request-id").?);
    try std.testing.expectEqualStrings("corr-external-1", res.header("x-correlation-id").?);

    // Handler should see both values separately
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"request_id\":\"req-external-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"correlation_id\":\"corr-external-1\"") != null);

    // Telemetry should have the correlation ID
    try std.testing.expectEqualStrings("corr-external-1", telemetry_last_correlation_id.?);
}

test "correlation id header name can be customized via config" {
    resetState(std.testing.allocator);
    defer resetState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "correlation-id-custom-header",
        .version = "0.0.1",
        .correlation_id_header = "x-trace-correlation",
    });
    defer app.deinit();

    app.setTelemetrySink(telemetrySink);
    try app.get("/test", correlationHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.requestWithHeaders(.GET, "/test", "", &.{
        .{ .name = "x-trace-correlation", .value = "custom-corr-99" },
    });
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);

    // Should use the custom header name for the response
    const response_corr_id = res.header("x-trace-correlation") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("custom-corr-99", response_corr_id);

    // Default header should not be present
    try std.testing.expect(res.header("x-correlation-id") == null);

    // Should still be available as a dependency
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"correlation_id\":\"custom-corr-99\"") != null);
    try std.testing.expectEqualStrings("custom-corr-99", telemetry_last_correlation_id.?);
}
