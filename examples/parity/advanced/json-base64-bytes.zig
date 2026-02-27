const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/json-base64-bytes/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/json-base64-bytes", implemented, .{
        .summary = "Parity implementation for advanced/json-base64-bytes/",
        .tags = &.{ "parity", "advanced" },
    });
}
