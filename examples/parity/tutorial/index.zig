const std = @import("std");
const zigmund = @import("zigmund");

fn readRoot(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .message = "Hello World",
    });
}

fn readHealth(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .status = "ok",
        .framework = "zigmund",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial", readRoot, .{
        .summary = "Tutorial root endpoint",
        .tags = &.{ "parity", "tutorial" },
    });
    try app.get("/tutorial/health", readHealth, .{
        .summary = "Tutorial health endpoint",
        .tags = &.{ "parity", "tutorial" },
    });
}
