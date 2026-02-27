const std = @import("std");
const zigmund = @import("zigmund");

var order_events: [8][]const u8 = undefined;
var order_event_count: usize = 0;
var cycle_resolver_calls: usize = 0;
var app_scope_resolver_calls: usize = 0;

fn resetOrderEvents() void {
    order_event_count = 0;
    @memset(order_events[0..], "");
}

fn pushOrderEvent(name: []const u8) void {
    if (order_event_count >= order_events.len) return;
    order_events[order_event_count] = name;
    order_event_count += 1;
}

fn authResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    pushOrderEvent("auth");
    return "alice";
}

fn auditResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    pushOrderEvent("audit");
    const auth = req.dependency("auth") orelse return error.MissingAuth;
    if (!std.mem.eql(u8, auth, "alice")) return error.MissingAuth;
    return "audit-ok";
}

fn traceResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    pushOrderEvent("trace");
    const auth = req.dependency("auth") orelse return error.MissingAuth;
    if (!std.mem.eql(u8, auth, "alice")) return error.MissingAuth;
    return "trace-ok";
}

fn orderedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .auth = req.dependency("auth") orelse "",
        .audit = req.dependency("audit") orelse "",
        .trace = req.dependency("trace") orelse "",
    });
}

fn cycleA(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    cycle_resolver_calls += 1;
    return "a";
}

fn cycleB(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    cycle_resolver_calls += 1;
    return "b";
}

fn simpleOk(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn tenantResolver(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    app_scope_resolver_calls += 1;
    return req.queryParam("tenant") orelse "default";
}

fn tenantHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .tenant = req.dependency("tenant") orelse "" });
}

test "dependency graph executes prerequisites before dependants" {
    resetOrderEvents();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "dep-order",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("auth", authResolver);
    try app.addDependency("audit", auditResolver);
    try app.addDependency("trace", traceResolver);

    try app.get("/ordered", orderedHandler, .{
        .dependencies = &.{
            .{ .name = "audit", .depends_on = &.{"auth"} },
            .{ .name = "trace", .depends_on = &.{"auth"} },
            .{ .name = "auth" },
        },
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/ordered");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"auth\":\"alice\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"audit\":\"audit-ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"trace\":\"trace-ok\"") != null);

    try std.testing.expectEqual(@as(usize, 3), order_event_count);
    try std.testing.expectEqualStrings("auth", order_events[0]);
    try std.testing.expectEqualStrings("audit", order_events[1]);
    try std.testing.expectEqualStrings("trace", order_events[2]);
}

test "dependency graph cycle returns 500 without executing resolvers" {
    cycle_resolver_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "dep-cycle",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("a", cycleA);
    try app.addDependency("b", cycleB);

    try app.get("/cycle", simpleOk, .{
        .dependencies = &.{
            .{ .name = "a", .depends_on = &.{"b"} },
            .{ .name = "b", .depends_on = &.{"a"} },
        },
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/cycle");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.internal_server_error, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "dependency cycle detected") != null);
    try std.testing.expectEqual(@as(usize, 0), cycle_resolver_calls);
}

test "app-scoped dependency cache is reused across requests" {
    app_scope_resolver_calls = 0;

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "dep-app-scope",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("tenant", tenantResolver);

    try app.get("/tenant", tenantHandler, .{
        .dependencies = &.{.{
            .name = "tenant",
            .use_cache = true,
            .cache_scope = .app,
        }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var first = try client.get("/tenant?tenant=acme");
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, first.status);
    try std.testing.expect(std.mem.indexOf(u8, first.body, "\"tenant\":\"acme\"") != null);

    var second = try client.get("/tenant?tenant=other");
    defer second.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, second.status);
    try std.testing.expect(std.mem.indexOf(u8, second.body, "\"tenant\":\"acme\"") != null);

    try std.testing.expectEqual(@as(usize, 1), app_scope_resolver_calls);
}
