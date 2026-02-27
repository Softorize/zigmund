const std = @import("std");
const zigmund = @import("zigmund");

fn authDependency(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
    _ = allocator;
    const token = req.queryParam("token") orelse return error.Unauthorized;
    if (!std.mem.eql(u8, token, "secret")) return error.Unauthorized;
    return "alice";
}

fn beforeTrace(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (req.queryParam("trace")) |trace_id| {
        try req.setDependencyValue("trace_id", trace_id);
    }
}

fn afterHeader(req: *zigmund.Request, res: *zigmund.Response, allocator: std.mem.Allocator) !void {
    _ = req;
    try res.setHeader(allocator, "x-middleware", "applied");
}

fn whoami(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .user = req.dependency("auth") orelse "unknown",
        .trace = req.dependency("trace_id") orelse "",
    });
}

test "dependency and middleware pipeline" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "deps",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addDependency("auth", authDependency);
    try app.addMiddleware(beforeTrace);
    try app.addMiddleware(afterHeader);

    try app.get("/whoami", whoami, .{
        .dependencies = &.{.{ .name = "auth", .use_cache = true }},
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var unauthorized = try client.get("/whoami?token=bad");
    defer unauthorized.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unauthorized, unauthorized.status);

    var authorized = try client.get("/whoami?token=secret&trace=req-1");
    defer authorized.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, authorized.status);
    try std.testing.expect(std.mem.indexOf(u8, authorized.body, "\"user\":\"alice\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, authorized.body, "\"trace\":\"req-1\"") != null);

    var has_mw_header = false;
    for (authorized.headers.items) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "x-middleware") and std.mem.eql(u8, header.value, "applied")) {
            has_mw_header = true;
            break;
        }
    }
    try std.testing.expect(has_mw_header);
}
