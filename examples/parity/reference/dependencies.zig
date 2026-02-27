const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/dependencies/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/dependencies", implemented, .{
        .summary = "Parity implementation for reference/dependencies/",
        .tags = &.{ "parity", "reference" },
    });
}
