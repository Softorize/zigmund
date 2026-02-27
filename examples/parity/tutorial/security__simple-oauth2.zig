const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/simple-oauth2/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__simple-oauth2", implemented, .{
        .summary = "Parity implementation for tutorial/security/simple-oauth2/",
        .tags = &.{ "parity", "tutorial" },
    });
}
