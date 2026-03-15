const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/dependencies-with-yield/";
var cleanup_calls = std.atomic.Value(usize).init(0);

const SessionResource = struct {
    label: []const u8,

    pub fn deinit(self: *SessionResource, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
        _ = cleanup_calls.fetchAdd(1, .monotonic);
    }
};

fn sessionProvider(req: *zigmund.Request) SessionResource {
    _ = req;
    return .{ .label = "yield-backed-session" };
}

fn implemented(session: zigmund.Depends(sessionProvider, .{}), allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .resource = session.value.?.label,
        .cleanup_calls_seen_before_response = cleanup_calls.load(.monotonic),
    });
}

fn cleanupCount(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .cleanup_calls = cleanup_calls.load(.monotonic),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__dependencies-with-yield", implemented, .{
        .summary = "Parity implementation for tutorial/dependencies/dependencies-with-yield/",
        .tags = &.{ "parity", "tutorial" },
    });
    try app.get("/tutorial/dependencies__dependencies-with-yield/cleanup-count", cleanupCount, .{
        .summary = "Observes automatic cleanup count for dependency resources",
        .tags = &.{ "parity", "tutorial" },
    });
}
