const std = @import("std");
const zigmund = @import("zigmund");

const child_state_value: []const u8 = "child";
const parent_mw_value: []const u8 = "yes";
const child_mw_value: []const u8 = "yes";

fn childItemsHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const value = req.appStateAs(*const []const u8, "who") orelse return error.TestUnexpectedResult;
    const parent_seen = req.stateAs(*const []const u8, "parent_mw") != null;
    const child_seen = req.stateAs(*const []const u8, "child_mw") != null;

    return zigmund.Response.json(allocator, .{
        .who = value.*,
        .parent_middleware = parent_seen,
        .child_middleware = child_seen,
    });
}

fn parentRootHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn parentMiddleware(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try req.setStateBorrowed("parent_mw", &parent_mw_value);
}

fn childMiddleware(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try req.setStateBorrowed("child_mw", &child_mw_value);
}

var lifecycle_log: [8]u8 = undefined;
var lifecycle_len: usize = 0;

fn lifecycleReset() void {
    lifecycle_len = 0;
}

fn lifecyclePush(ch: u8) void {
    lifecycle_log[lifecycle_len] = ch;
    lifecycle_len += 1;
}

fn parentStartup() !void {
    lifecyclePush('P');
}

fn childStartup() !void {
    lifecyclePush('C');
}

fn childShutdown() !void {
    lifecyclePush('c');
}

fn parentShutdown() !void {
    lifecyclePush('p');
}

test "mounted app delegates routes without merging them into parent openapi" {
    var child = try zigmund.App.init(std.testing.allocator, .{
        .title = "Child API",
        .version = "0.0.1",
    });
    defer child.deinit();
    try child.setStateBorrowed("who", &child_state_value);
    try child.get("/items", childItemsHandler, .{});
    try child.addMiddleware(childMiddleware);

    var parent = try zigmund.App.init(std.testing.allocator, .{
        .title = "Parent API",
        .version = "0.0.1",
    });
    defer parent.deinit();
    try parent.get("/", parentRootHandler, .{});
    try parent.addMiddleware(parentMiddleware);
    try parent.mount("/child", &child);

    var child_res = try parent.dispatchSynthetic(.GET, "/child/items", "");
    defer child_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, child_res.status);
    try std.testing.expect(std.mem.indexOf(u8, child_res.body, "\"who\":\"child\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, child_res.body, "\"parent_middleware\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, child_res.body, "\"child_middleware\":true") != null);

    var missing = try parent.dispatchSynthetic(.GET, "/items", "");
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_found, missing.status);

    const parent_doc = try parent.openapi();
    try std.testing.expect(std.mem.indexOf(u8, parent_doc, "\"/child/items\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, parent_doc, "\"/\"") != null);

    const child_doc = try child.openapi();
    try std.testing.expect(std.mem.indexOf(u8, child_doc, "\"/items\"") != null);
}

test "mounted app docs and openapi are served under the mounted prefix" {
    var child = try zigmund.App.init(std.testing.allocator, .{
        .title = "Child Docs",
        .version = "0.0.1",
    });
    defer child.deinit();
    try child.get("/items", childItemsHandler, .{});
    try child.setStateBorrowed("who", &child_state_value);

    var parent = try zigmund.App.init(std.testing.allocator, .{
        .title = "Parent Docs",
        .version = "0.0.1",
    });
    defer parent.deinit();
    try parent.get("/", parentRootHandler, .{});
    try parent.mount("/child", &child);

    var docs_res = try parent.dispatchSynthetic(.GET, "/child/docs", "");
    defer docs_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, docs_res.status);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "\"/child/openapi.json\"") != null);

    var openapi_res = try parent.dispatchSynthetic(.GET, "/child/openapi.json", "");
    defer openapi_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, openapi_res.status);
    try std.testing.expect(std.mem.indexOf(u8, openapi_res.body, "\"/items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, openapi_res.body, "\"/child/items\"") == null);
}

test "mounted app lifecycle runs after parent startup and before parent shutdown" {
    lifecycleReset();

    var child = try zigmund.App.init(std.testing.allocator, .{
        .title = "Child Lifecycle",
        .version = "0.0.1",
    });
    defer child.deinit();
    try child.lifespan(childStartup, childShutdown);

    var parent = try zigmund.App.init(std.testing.allocator, .{
        .title = "Parent Lifecycle",
        .version = "0.0.1",
    });
    defer parent.deinit();
    try parent.lifespan(parentStartup, parentShutdown);
    try parent.mount("/child", &child);

    var client = zigmund.TestClient.init(std.testing.allocator, &parent);
    defer client.deinit();

    try client.start();
    try client.close();

    try std.testing.expectEqualStrings("PCcp", lifecycle_log[0..lifecycle_len]);
}
