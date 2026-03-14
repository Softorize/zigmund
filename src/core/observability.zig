const std = @import("std");
const App = @import("app.zig").App;
const Request = @import("../http/request.zig").Request;

pub const StructuredLogRedactionOptions = struct {
    marker: []const u8 = "[redacted]",
    redact_tracestate: bool = true,
    redact_baggage: bool = true,
    redact_remote_addr: bool = true,
    redact_user_agent: bool = true,
};

pub fn elapsedMicros(start_ns: i128) u64 {
    const now_ns = std.time.nanoTimestamp();
    const latency_ns: i128 = if (now_ns > start_ns) now_ns - start_ns else 0;
    return @intCast(@divFloor(latency_ns, 1_000));
}

pub fn observabilityPath(req: *const Request) []const u8 {
    return req.dependency("zigmund.route.path_template") orelse req.path;
}

pub fn jsonTelemetrySink(event: App.TelemetryEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"telemetry\",\"request_id\":{f},\"trace_id\":{f},\"span_id\":{f},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d}}}",
        .{
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.trace_id, .{}),
            std.json.fmt(event.span_id, .{}),
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

pub fn jsonTraceSink(event: App.TraceEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"trace\",\"request_id\":{f},\"trace_context\":{f},\"tracestate\":{f},\"baggage\":{f},\"trace_id\":{f},\"span_id\":{f},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d}}}",
        .{
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.trace_context, .{}),
            std.json.fmt(event.tracestate, .{}),
            std.json.fmt(event.baggage, .{}),
            std.json.fmt(event.trace_id, .{}),
            std.json.fmt(event.span_id, .{}),
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

pub fn redactedJsonTraceSink(event: App.TraceEvent, allocator: std.mem.Allocator) !void {
    try jsonTraceSink(redactTraceEvent(event, .{}), allocator);
}

pub fn jsonAccessLogSink(event: App.AccessLogEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"access_log\",\"request_id\":{f},\"trace_context\":{f},\"tracestate\":{f},\"baggage\":{f},\"trace_id\":{f},\"span_id\":{f},\"method\":{f},\"path\":{f},\"scheme\":{f},\"host\":{f},\"status\":{d},\"latency_us\":{d},\"remote_addr\":{f},\"user_agent\":{f}}}",
        .{
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.trace_context, .{}),
            std.json.fmt(event.tracestate, .{}),
            std.json.fmt(event.baggage, .{}),
            std.json.fmt(event.trace_id, .{}),
            std.json.fmt(event.span_id, .{}),
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            std.json.fmt(event.scheme, .{}),
            std.json.fmt(event.host, .{}),
            @intFromEnum(event.status),
            event.latency_us,
            std.json.fmt(event.remote_addr, .{}),
            std.json.fmt(event.user_agent, .{}),
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

pub fn redactedJsonAccessLogSink(event: App.AccessLogEvent, allocator: std.mem.Allocator) !void {
    try jsonAccessLogSink(redactAccessLogEvent(event, .{}), allocator);
}

pub fn jsonMetricsSink(event: App.MetricsEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"metrics\",\"name\":{f},\"value\":{d},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d}}}",
        .{
            std.json.fmt(event.name, .{}),
            event.value,
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

pub fn jsonAuditSink(event: App.AuditEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"audit\",\"category\":{f},\"action\":{f},\"request_id\":{f},\"method\":{f},\"path\":{f},\"detail\":{f}}}",
        .{
            std.json.fmt(event.category, .{}),
            std.json.fmt(event.action, .{}),
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.method, .{}),
            std.json.fmt(event.path, .{}),
            std.json.fmt(event.detail, .{}),
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

pub fn writeStderrLine(line: []const u8) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    try stderr_writer.interface.writeAll(line);
    try stderr_writer.interface.writeAll("\n");
    try stderr_writer.interface.flush();
}

pub fn redactTraceEvent(
    event: App.TraceEvent,
    options: StructuredLogRedactionOptions,
) App.TraceEvent {
    var sanitized = event;
    if (options.redact_tracestate and sanitized.tracestate.len != 0) {
        sanitized.tracestate = options.marker;
    }
    if (options.redact_baggage and sanitized.baggage.len != 0) {
        sanitized.baggage = options.marker;
    }
    return sanitized;
}

pub fn redactAccessLogEvent(
    event: App.AccessLogEvent,
    options: StructuredLogRedactionOptions,
) App.AccessLogEvent {
    var sanitized = event;
    if (options.redact_tracestate and sanitized.tracestate.len != 0) {
        sanitized.tracestate = options.marker;
    }
    if (options.redact_baggage and sanitized.baggage.len != 0) {
        sanitized.baggage = options.marker;
    }
    if (options.redact_remote_addr and sanitized.remote_addr.len != 0) {
        sanitized.remote_addr = options.marker;
    }
    if (options.redact_user_agent and sanitized.user_agent.len != 0) {
        sanitized.user_agent = options.marker;
    }
    return sanitized;
}

test "trace event redaction only masks configured fields" {
    const event: App.TraceEvent = .{
        .request_id = "req-1",
        .trace_context = "00-abc-123-01",
        .tracestate = "vendor=1",
        .baggage = "user.id=42",
        .trace_id = "abc",
        .span_id = "123",
        .method = .GET,
        .path = "/orders",
        .status = .ok,
        .latency_us = 10,
    };

    const sanitized = redactTraceEvent(event, .{
        .marker = "***",
        .redact_tracestate = true,
        .redact_baggage = false,
    });

    try std.testing.expectEqualStrings("***", sanitized.tracestate);
    try std.testing.expectEqualStrings("user.id=42", sanitized.baggage);
    try std.testing.expectEqualStrings("00-abc-123-01", sanitized.trace_context);
}

test "access log redaction masks client metadata by default" {
    const event: App.AccessLogEvent = .{
        .request_id = "req-1",
        .trace_context = "00-abc-123-01",
        .tracestate = "vendor=1",
        .baggage = "tenant=acme",
        .trace_id = "abc",
        .span_id = "123",
        .method = .GET,
        .path = "/orders",
        .scheme = "https",
        .host = "example.com",
        .status = .ok,
        .latency_us = 10,
        .remote_addr = "203.0.113.7",
        .user_agent = "curl/8.0.0",
    };

    const sanitized = redactAccessLogEvent(event, .{});

    try std.testing.expectEqualStrings("[redacted]", sanitized.tracestate);
    try std.testing.expectEqualStrings("[redacted]", sanitized.baggage);
    try std.testing.expectEqualStrings("[redacted]", sanitized.remote_addr);
    try std.testing.expectEqualStrings("[redacted]", sanitized.user_agent);
}
