const std = @import("std");

pub const Registry = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},
    entries: std.ArrayListUnmanaged(Entry) = .empty,

    const Entry = struct {
        method: std.http.Method,
        path: []u8,
        status: std.http.Status,
        requests_total: u64 = 0,
        latency_us_total: u128 = 0,
        latency_us_count: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items) |entry| {
            self.allocator.free(entry.path);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn observe(
        self: *Registry,
        method: std.http.Method,
        path: []const u8,
        status: std.http.Status,
        latency_us: u64,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.entries.items) |*entry| {
            if (entry.method != method) continue;
            if (entry.status != status) continue;
            if (!std.mem.eql(u8, entry.path, path)) continue;

            entry.requests_total += 1;
            entry.latency_us_total += latency_us;
            entry.latency_us_count += 1;
            return;
        }

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        try self.entries.append(self.allocator, .{
            .method = method,
            .path = owned_path,
            .status = status,
            .requests_total = 1,
            .latency_us_total = latency_us,
            .latency_us_count = 1,
        });
    }

    pub fn renderPrometheus(self: *Registry, allocator: std.mem.Allocator) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var writer = out.writer(allocator);

        try writer.writeAll("# HELP zigmund_http_requests_total Total HTTP requests handled by Zigmund.\n");
        try writer.writeAll("# TYPE zigmund_http_requests_total counter\n");
        for (self.entries.items) |entry| {
            try writeMetricSample(&writer, "zigmund_http_requests_total", entry, entry.requests_total);
        }

        try writer.writeAll("# HELP zigmund_http_request_latency_us_total Total accumulated request latency in microseconds.\n");
        try writer.writeAll("# TYPE zigmund_http_request_latency_us_total counter\n");
        for (self.entries.items) |entry| {
            try writeMetricSample(&writer, "zigmund_http_request_latency_us_total", entry, entry.latency_us_total);
        }

        try writer.writeAll("# HELP zigmund_http_request_latency_us_count Total number of request latency samples.\n");
        try writer.writeAll("# TYPE zigmund_http_request_latency_us_count counter\n");
        for (self.entries.items) |entry| {
            try writeMetricSample(&writer, "zigmund_http_request_latency_us_count", entry, entry.latency_us_count);
        }

        return out.toOwnedSlice(allocator);
    }
};

fn writeMetricSample(writer: anytype, name: []const u8, entry: Registry.Entry, value: anytype) !void {
    try writer.print("{s}{{method=\"{s}\",path=\"", .{
        name,
        @tagName(entry.method),
    });
    try writeEscapedLabelValue(writer, entry.path);
    try writer.print("\",status=\"{d}\"}} {d}\n", .{
        @intFromEnum(entry.status),
        value,
    });
}

fn writeEscapedLabelValue(writer: anytype, value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            else => try writer.writeByte(ch),
        }
    }
}

test "metrics registry observes and renders prometheus text format" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.observe(.GET, "/ping", .ok, 120);
    try registry.observe(.GET, "/ping", .ok, 80);
    try registry.observe(.POST, "/items", .created, 200);

    const metrics_text = try registry.renderPrometheus(std.testing.allocator);
    defer std.testing.allocator.free(metrics_text);

    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics_text,
        "zigmund_http_requests_total{method=\"GET\",path=\"/ping\",status=\"200\"} 2",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics_text,
        "zigmund_http_request_latency_us_total{method=\"GET\",path=\"/ping\",status=\"200\"} 200",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        metrics_text,
        "zigmund_http_request_latency_us_count{method=\"POST\",path=\"/items\",status=\"201\"} 1",
    ) != null);
}
