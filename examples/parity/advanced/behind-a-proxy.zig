const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/behind-a-proxy/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/behind-a-proxy", implemented, .{
        .summary = "Parity implementation for advanced/behind-a-proxy/",
        .tags = &.{ "parity", "advanced" },
    });
}
