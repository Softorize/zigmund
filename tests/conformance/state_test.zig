const std = @import("std");
const zigmund = @import("zigmund");

const AppStatePayload = struct {
    greeting: []const u8,
};

const OwnedState = struct {
    value: usize,
};

var app_state_payload = AppStatePayload{ .greeting = "hello" };
var request_state_seed: usize = 41;
var request_state_cleanup_calls: usize = 0;
var app_state_cleanup_calls: usize = 0;

fn appStateHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const payload = req.appStateAs(*const AppStatePayload, "payload") orelse return error.TestUnexpectedResult;
    return zigmund.Response.json(allocator, .{ .greeting = payload.greeting });
}

fn requestStateMiddleware(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try req.setStateBorrowed("marker", &request_state_seed);
}

fn requestStateHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const marker = req.stateAs(*const usize, "marker") orelse return error.TestUnexpectedResult;
    return zigmund.Response.json(allocator, .{ .marker = marker.* });
}

fn ownedStateCleanup(ptr: ?*anyopaque, allocator: std.mem.Allocator) void {
    const raw = ptr orelse return;
    const owned: *OwnedState = @ptrCast(@alignCast(raw));
    allocator.destroy(owned);
    request_state_cleanup_calls += 1;
}

fn appOwnedStateCleanup(ptr: ?*anyopaque, allocator: std.mem.Allocator) void {
    const raw = ptr orelse return;
    const owned: *OwnedState = @ptrCast(@alignCast(raw));
    allocator.destroy(owned);
    app_state_cleanup_calls += 1;
}

fn ownedStateHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const owned = try allocator.create(OwnedState);
    owned.* = .{ .value = 7 };
    try req.setStateOwned("owned", owned, ownedStateCleanup);

    const current = req.stateAs(*OwnedState, "owned") orelse return error.TestUnexpectedResult;
    return zigmund.Response.json(allocator, .{ .value = current.value });
}

test "app state is available from request handlers" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "app-state",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.setStateBorrowed("payload", &app_state_payload);
    try app.get("/state", appStateHandler, .{});

    var res = try app.dispatchSynthetic(.GET, "/state", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"greeting\":\"hello\"") != null);
}

test "request state is available during request pipeline" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "request-state",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addMiddleware(zigmund.Middleware{
        .name = "request-state",
        .request_hook = requestStateMiddleware,
    });
    try app.get("/state", requestStateHandler, .{});

    var res = try app.dispatchSynthetic(.GET, "/state", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"marker\":41") != null);
}

test "owned request state is cleaned up at end of request" {
    request_state_cleanup_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "request-state-cleanup",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/owned", ownedStateHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var res = try client.get("/owned");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expectEqual(@as(usize, 1), request_state_cleanup_calls);
}

test "owned app state is cleaned up on app deinit" {
    app_state_cleanup_calls = 0;

    {
        var app = try zigmund.App.init(std.testing.allocator, .{
            .title = "app-state-cleanup",
            .version = "0.0.1",
        });

        const owned = try std.testing.allocator.create(OwnedState);
        owned.* = .{ .value = 9 };
        try app.setStateOwned("owned", owned, appOwnedStateCleanup);
        app.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), app_state_cleanup_calls);
}
