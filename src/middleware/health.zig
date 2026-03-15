const std = @import("std");

/// Function type for health check probes.
pub const HealthCheckFn = *const fn () anyerror!void;

/// A named health check entry.
pub const HealthCheckEntry = struct {
    name: []const u8,
    check: HealthCheckFn,
};

/// Result for a single check within the readiness probe.
const CheckResult = struct {
    name: []const u8,
    ok: bool,
    err_msg: ?[]const u8 = null,
};

/// Build the liveness JSON response (always healthy).
pub fn liveResponse(allocator: std.mem.Allocator) !LiveResponse {
    const body =
        \\{"status":"alive"}
    ;
    const owned = try allocator.dupe(u8, body);
    return .{ .body = owned, .status = .ok };
}

/// Build the readiness JSON response by running all registered checks.
pub fn readyResponse(allocator: std.mem.Allocator, checks: []const HealthCheckEntry) !ReadyResult {
    var all_ok = true;

    // Build the checks JSON object
    var parts: std.ArrayList(u8) = .empty;
    defer parts.deinit(allocator);

    try parts.appendSlice(allocator, "{\"status\":");

    // First pass: run all checks and collect results
    var results: std.ArrayList(CheckResult) = .empty;
    defer {
        for (results.items) |r| {
            if (r.err_msg) |msg| allocator.free(msg);
        }
        results.deinit(allocator);
    }

    for (checks) |entry| {
        entry.check() catch |err| {
            all_ok = false;
            const msg = try std.fmt.allocPrint(allocator, "failed: {s}", .{@errorName(err)});
            try results.append(allocator, .{ .name = entry.name, .ok = false, .err_msg = msg });
            continue;
        };
        try results.append(allocator, .{ .name = entry.name, .ok = true });
    }

    if (all_ok) {
        try parts.appendSlice(allocator, "\"healthy\"");
    } else {
        try parts.appendSlice(allocator, "\"unhealthy\"");
    }

    // Build checks object
    try parts.appendSlice(allocator, ",\"checks\":{");
    for (results.items, 0..) |r, i| {
        if (i > 0) try parts.append(allocator, ',');
        try parts.append(allocator, '"');
        try parts.appendSlice(allocator, r.name);
        try parts.appendSlice(allocator, "\":\"");
        if (r.ok) {
            try parts.appendSlice(allocator, "ok");
        } else {
            // Escape the error message for JSON
            if (r.err_msg) |msg| {
                for (msg) |c| {
                    switch (c) {
                        '"' => try parts.appendSlice(allocator, "\\\""),
                        '\\' => try parts.appendSlice(allocator, "\\\\"),
                        else => try parts.append(allocator, c),
                    }
                }
            }
        }
        try parts.append(allocator, '"');
    }
    try parts.appendSlice(allocator, "}}");

    const body = try allocator.dupe(u8, parts.items);
    const status: std.http.Status = if (all_ok) .ok else .service_unavailable;
    return .{ .body = body, .status = status };
}

pub const LiveResponse = struct {
    body: []u8,
    status: std.http.Status,
};

pub const ReadyResult = struct {
    body: []u8,
    status: std.http.Status,
};
