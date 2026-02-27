const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/response-change-status-code/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-change-status-code", implemented, .{
        .summary = "Parity implementation for advanced/response-change-status-code/",
        .tags = &.{ "parity", "advanced" },
    });
}
