const std = @import("std");
const zigmund = @import("zigmund");

var cleanup_calls: usize = 0;
var cleanup_last_value: [32]u8 = undefined;
var cleanup_last_value_len: usize = 0;

fn resetCleanupState() void {
    cleanup_calls = 0;
    cleanup_last_value_len = 0;
    @memset(cleanup_last_value[0..], 0);
}

fn authResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "alice";
}

fn authCleanup(
    req: *zigmund.Request,
    key: []const u8,
    value: []const u8,
    allocator: std.mem.Allocator,
) !void {
    _ = req;
    _ = key;
    _ = allocator;
    cleanup_calls += 1;
    cleanup_last_value_len = @min(cleanup_last_value.len, value.len);
    @memcpy(cleanup_last_value[0..cleanup_last_value_len], value[0..cleanup_last_value_len]);
}

fn okHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .user = req.dependency("auth") orelse "",
    });
}

fn failHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return error.Outage;
}

test "dependency cleanup runs for success and error responses" {
    resetCleanupState();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "dependency-cleanup",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependencyWithCleanup("auth", authResolver, authCleanup);
    try app.get("/ok", okHandler, .{
        .dependencies = &.{.{ .name = "auth" }},
    });
    try app.get("/fail", failHandler, .{
        .dependencies = &.{.{ .name = "auth" }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var ok = try client.get("/ok");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"user\":\"alice\"") != null);
    try std.testing.expectEqual(@as(usize, 1), cleanup_calls);
    try std.testing.expectEqualStrings("alice", cleanup_last_value[0..cleanup_last_value_len]);

    var fail = try client.get("/fail");
    defer fail.deinit(std.testing.allocator);
    try std.testing.expectEqual(.internal_server_error, fail.status);
    try std.testing.expectEqual(@as(usize, 2), cleanup_calls);
}
