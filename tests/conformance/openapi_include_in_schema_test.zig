const std = @import("std");
const zigmund = @import("zigmund");

fn okHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("ok");
}

test "route include_in_schema false hides route from openapi" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-include-route",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/visible", okHandler, .{});
    try app.get("/hidden", okHandler, .{ .include_in_schema = false });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/visible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/hidden\"") == null);
}

test "includeRouter include_in_schema false hides included routes from openapi" {
    var sub = zigmund.Router.init(std.testing.allocator);
    defer sub.deinit();

    try sub.addHttpRoute(.GET, "/internal", okHandler, .{});

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-include-router",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.includeRouter("/api", &sub, .{ .include_in_schema = false });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var res = try client.get("/api/internal");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/api/internal\"") == null);
}
