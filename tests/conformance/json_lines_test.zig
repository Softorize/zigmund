const std = @import("std");
const zigmund = @import("zigmund");

const Metric = struct {
    ts: u64,
    value: f64,
    label: []const u8,
};

test "jsonLines serializes a slice of structs as NDJSON" {
    const items = [_]Metric{
        .{ .ts = 1000, .value = 3.14, .label = "cpu" },
        .{ .ts = 2000, .value = 2.72, .label = "mem" },
        .{ .ts = 3000, .value = 1.41, .label = "disk" },
    };

    var res = try zigmund.Response.jsonLines(std.testing.allocator, &items);
    defer res.deinit(std.testing.allocator);

    // Verify content-type
    try std.testing.expectEqualStrings("application/x-ndjson", res.content_type);
    try std.testing.expectEqual(.ok, res.status);

    // Split body into lines and verify each is valid JSON
    var line_iter = std.mem.splitScalar(u8, res.body, '\n');
    var count: usize = 0;
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(Metric, std.testing.allocator, line, .{});
        defer parsed.deinit();
        try std.testing.expectEqualStrings(items[count].label, parsed.value.label);
        try std.testing.expectEqual(items[count].ts, parsed.value.ts);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "jsonLines produces empty body for empty slice" {
    const items = [_]Metric{};

    var res = try zigmund.Response.jsonLines(std.testing.allocator, &items);
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/x-ndjson", res.content_type);
    try std.testing.expectEqualStrings("", res.body);
}

test "jsonLinesRaw joins pre-serialized JSON strings" {
    const lines = [_][]const u8{
        "{\"event\":\"start\"}",
        "{\"event\":\"stop\",\"code\":0}",
    };

    var res = try zigmund.Response.jsonLinesRaw(std.testing.allocator, &lines);
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/x-ndjson", res.content_type);
    try std.testing.expectEqualStrings(
        "{\"event\":\"start\"}\n{\"event\":\"stop\",\"code\":0}\n",
        res.body,
    );

    // Each line must parse as valid JSON
    var line_iter = std.mem.splitScalar(u8, res.body, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
    }
}

test "jsonLines single item produces one line" {
    const items = [_]Metric{
        .{ .ts = 42, .value = 9.81, .label = "gravity" },
    };

    var res = try zigmund.Response.jsonLines(std.testing.allocator, &items);
    defer res.deinit(std.testing.allocator);

    // Body should be exactly one JSON object followed by newline
    try std.testing.expect(std.mem.endsWith(u8, res.body, "\n"));

    // Count newlines - should be exactly 1
    var newline_count: usize = 0;
    for (res.body) |c| {
        if (c == '\n') newline_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), newline_count);

    // Parse the single line
    const line = std.mem.trimRight(u8, res.body, "\n");
    const parsed = try std.json.parseFromSlice(Metric, std.testing.allocator, line, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("gravity", parsed.value.label);
}
