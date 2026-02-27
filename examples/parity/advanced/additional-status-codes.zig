const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/additional-status-codes/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/additional-status-codes", implemented, .{
        .summary = "Parity implementation for advanced/additional-status-codes/",
        .tags = &.{ "parity", "advanced" },
    });
}
