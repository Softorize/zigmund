const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/extra-models/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/extra-models", implemented, .{
        .summary = "Parity implementation for tutorial/extra-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
