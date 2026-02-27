const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/dependencies-with-yield/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__dependencies-with-yield", implemented, .{
        .summary = "Parity implementation for tutorial/dependencies/dependencies-with-yield/",
        .tags = &.{ "parity", "tutorial" },
    });
}
