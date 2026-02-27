const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/testing-database/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/testing-database", implemented, .{
        .summary = "Parity implementation for how-to/testing-database/",
        .tags = &.{ "parity", "how-to" },
    });
}
