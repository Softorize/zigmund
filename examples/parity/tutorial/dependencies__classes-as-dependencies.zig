const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/dependencies/classes-as-dependencies/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__classes-as-dependencies", implemented, .{
        .summary = "Parity implementation for tutorial/dependencies/classes-as-dependencies/",
        .tags = &.{ "parity", "tutorial" },
    });
}
