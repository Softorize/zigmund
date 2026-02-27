const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/cookie-param-models/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/cookie-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/cookie-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
