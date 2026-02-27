const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/general/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/general", implemented, .{
        .summary = "Parity implementation for how-to/general/",
        .tags = &.{ "parity", "how-to" },
    });
}
