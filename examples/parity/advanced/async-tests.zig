const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/async-tests/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/async-tests", implemented, .{
        .summary = "Parity implementation for advanced/async-tests/",
        .tags = &.{ "parity", "advanced" },
    });
}
