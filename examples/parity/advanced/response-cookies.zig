const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/response-cookies/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-cookies", implemented, .{
        .summary = "Parity implementation for advanced/response-cookies/",
        .tags = &.{ "parity", "advanced" },
    });
}
