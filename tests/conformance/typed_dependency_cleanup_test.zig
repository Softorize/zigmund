const std = @import("std");
const zigmund = @import("zigmund");

var cleanup_calls: usize = 0;
var cleanup_saw_session: bool = false;

const SessionResource = struct {
    label: []const u8,

    pub fn deinit(self: *SessionResource, allocator: std.mem.Allocator) !void {
        _ = allocator;
        cleanup_calls += 1;
        cleanup_saw_session = cleanup_saw_session or std.mem.eql(u8, self.label, "db-session");
    }
};

fn resetCleanupState() void {
    cleanup_calls = 0;
    cleanup_saw_session = false;
}

fn sessionProvider(req: *zigmund.Request) SessionResource {
    _ = req;
    return .{ .label = "db-session" };
}

fn okHandler(
    one: zigmund.Depends(sessionProvider, .{}),
    two: zigmund.Depends(sessionProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .one = one.value.?.label,
        .two = two.value.?.label,
    });
}

fn errorHandler(
    dep: zigmund.Depends(sessionProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = dep;
    _ = allocator;
    return error.DependencyFailure;
}

test "typed depends resources clean up once after cached success" {
    resetCleanupState();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "typed-dependency-cleanup",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/ok", okHandler, .{});

    var res = try app.dispatchSynthetic(.GET, "/ok", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"one\":\"db-session\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"two\":\"db-session\"") != null);
    try std.testing.expectEqual(@as(usize, 1), cleanup_calls);
    try std.testing.expect(cleanup_saw_session);
}

test "typed depends resources clean up on handler errors" {
    resetCleanupState();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "typed-dependency-cleanup-error",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/fail", errorHandler, .{});

    var res = try app.dispatchSynthetic(.GET, "/fail", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.internal_server_error, res.status);
    try std.testing.expectEqual(@as(usize, 1), cleanup_calls);
    try std.testing.expect(cleanup_saw_session);
}
