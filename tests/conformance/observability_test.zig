const std = @import("std");
const zigmund = @import("zigmund");

var telemetry_event_count: usize = 0;
var telemetry_last_status: ?std.http.Status = null;
var telemetry_last_latency_us: u64 = 0;
var telemetry_last_path: ?[]u8 = null;
var telemetry_last_request_id: ?[]u8 = null;
var trace_event_count: usize = 0;
var trace_last_trace_context: ?[]u8 = null;
var trace_last_request_id: ?[]u8 = null;
var access_log_event_count: usize = 0;
var access_log_last_trace_context: ?[]u8 = null;
var access_log_last_user_agent: ?[]u8 = null;
var metrics_event_count: usize = 0;
var metrics_last_name: ?[]u8 = null;
var metrics_last_value: f64 = 0;
var audit_event_count: usize = 0;
var audit_last_category: ?[]u8 = null;
var audit_last_action: ?[]u8 = null;
var audit_last_method: ?[]u8 = null;
var audit_last_path: ?[]u8 = null;
var audit_last_detail: ?[]u8 = null;

fn resetTelemetryState(allocator: std.mem.Allocator) void {
    telemetry_event_count = 0;
    telemetry_last_status = null;
    telemetry_last_latency_us = 0;

    if (telemetry_last_path) |path| allocator.free(path);
    telemetry_last_path = null;

    if (telemetry_last_request_id) |request_id| allocator.free(request_id);
    telemetry_last_request_id = null;

    trace_event_count = 0;
    if (trace_last_trace_context) |trace_context| allocator.free(trace_context);
    trace_last_trace_context = null;
    if (trace_last_request_id) |request_id| allocator.free(request_id);
    trace_last_request_id = null;

    access_log_event_count = 0;
    if (access_log_last_trace_context) |trace_context| allocator.free(trace_context);
    access_log_last_trace_context = null;
    if (access_log_last_user_agent) |user_agent| allocator.free(user_agent);
    access_log_last_user_agent = null;

    metrics_event_count = 0;
    if (metrics_last_name) |name| allocator.free(name);
    metrics_last_name = null;
    metrics_last_value = 0;

    audit_event_count = 0;
    if (audit_last_category) |category| allocator.free(category);
    audit_last_category = null;
    if (audit_last_action) |action| allocator.free(action);
    audit_last_action = null;
    if (audit_last_method) |method| allocator.free(method);
    audit_last_method = null;
    if (audit_last_path) |path| allocator.free(path);
    audit_last_path = null;
    if (audit_last_detail) |detail| allocator.free(detail);
    audit_last_detail = null;
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

fn traceSink(event: zigmund.App.TraceEvent, allocator: std.mem.Allocator) !void {
    if (trace_last_trace_context) |trace_context| allocator.free(trace_context);
    if (trace_last_request_id) |request_id| allocator.free(request_id);

    trace_last_trace_context = try allocator.dupe(u8, event.trace_context);
    trace_last_request_id = try allocator.dupe(u8, event.request_id);
    trace_event_count += 1;
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

fn auditSink(event: zigmund.App.AuditEvent, allocator: std.mem.Allocator) !void {
    if (audit_last_category) |category| allocator.free(category);
    if (audit_last_action) |action| allocator.free(action);
    if (audit_last_method) |method| allocator.free(method);
    if (audit_last_path) |path| allocator.free(path);
    if (audit_last_detail) |detail| allocator.free(detail);

    audit_last_category = try allocator.dupe(u8, event.category);
    audit_last_action = try allocator.dupe(u8, event.action);
    audit_last_method = try allocator.dupe(u8, event.method);
    audit_last_path = try allocator.dupe(u8, event.path);
    audit_last_detail = try allocator.dupe(u8, event.detail);
    audit_event_count += 1;
}

fn observabilityHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .request_id = req.dependency("request_id") orelse "",
        .trace_context = req.dependency("trace_context") orelse "",
    });
}

fn secureHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn authDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;

    const bearer = zigmund.HTTPBearer{};
    const creds = (try bearer.resolve(req)) orelse return null;
    try zigmund.security.setGrantedScopesRaw(req, req.header("x-scopes") orelse "");
    return creds.credentials;
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
    app.setTraceSink(traceSink);
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
    try std.testing.expectEqual(@as(usize, 1), trace_event_count);
    try std.testing.expectEqualStrings("", trace_last_trace_context.?);
    try std.testing.expectEqualStrings(generated_request_id, trace_last_request_id.?);
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
    try std.testing.expectEqual(@as(usize, 2), trace_event_count);
    try std.testing.expectEqualStrings("trace-123", trace_last_trace_context.?);
    try std.testing.expectEqualStrings("external-request-id-1", trace_last_request_id.?);
    try std.testing.expectEqual(@as(usize, 2), access_log_event_count);
    try std.testing.expectEqualStrings("trace-123", access_log_last_trace_context.?);
    try std.testing.expectEqualStrings("zigmund-test", access_log_last_user_agent.?);
    try std.testing.expectEqual(@as(usize, 4), metrics_event_count);
}

test "audit sink receives auth failure events" {
    resetTelemetryState(std.testing.allocator);
    defer resetTelemetryState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "audit-auth",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setAuditSink(auditSink);
    try app.addDependency("auth_dep", authDependency);
    try app.addSecurityScheme("auth_dep", .{
        .oauth2 = .{
            .flows = .{
                .password = .{
                    .token_url = "/token",
                    .scopes = &.{.{ .name = "admin" }},
                },
            },
        },
    });
    try app.get("/secure", secureHandler, .{
        .dependencies = &.{.{
            .name = "auth_dep",
            .scopes = &.{"admin"},
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/secure");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);
    try std.testing.expectEqual(@as(usize, 1), audit_event_count);
    try std.testing.expectEqualStrings("auth", audit_last_category.?);
    try std.testing.expectEqualStrings("http_unauthorized", audit_last_action.?);
    try std.testing.expectEqualStrings("GET", audit_last_method.?);
    try std.testing.expectEqualStrings("/secure", audit_last_path.?);

    var insufficient = try client.requestWithHeaders(.GET, "/secure", "", &.{
        .{ .name = "authorization", .value = "Bearer token-a" },
        .{ .name = "x-scopes", .value = "user" },
    });
    defer insufficient.deinit(std.testing.allocator);
    try std.testing.expectEqual(.forbidden, insufficient.status);
    try std.testing.expectEqual(@as(usize, 2), audit_event_count);
    try std.testing.expectEqualStrings("http_insufficient_scope", audit_last_action.?);
}
