const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/using-request-directly/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/using-request-directly", implemented, .{
        .summary = "Parity implementation for advanced/using-request-directly/",
        .tags = &.{ "parity", "advanced" },
    });
}
