const std = @import("std");
const zigmund = @import("zigmund");

fn outerDep(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "outer";
}

fn innerDep(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = req;
    _ = allocator;
    return "inner";
}

fn subHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .outer = req.dependency("outer_dep"),
        .inner = req.dependency("inner_dep"),
    });
}

test "includeRouter merges tags and dependencies with include-level values first" {
    var sub = zigmund.Router.init(std.testing.allocator);
    defer sub.deinit();

    try sub.addHttpRoute(.GET, "/items", subHandler, .{
        .tags = &.{"inner"},
        .dependencies = &.{.{ .name = "inner_dep" }},
    });

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "include-router-merge",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("outer_dep", outerDep);
    try app.addDependency("inner_dep", innerDep);

    try app.includeRouter("/v1", &sub, .{
        .tags = &.{"outer"},
        .dependencies = &.{.{ .name = "outer_dep" }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var response = try client.get("/v1/items");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"outer\":\"outer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"inner\":\"inner\"") != null);

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/v1/items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"tags\":[\"outer\",\"inner\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-zigmund-dependencies\"") != null);

    const outer_pos = std.mem.indexOf(u8, doc, "\"name\":\"outer_dep\"") orelse unreachable;
    const inner_pos = std.mem.indexOf(u8, doc, "\"name\":\"inner_dep\"") orelse unreachable;
    try std.testing.expect(outer_pos < inner_pos);
}
