const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/get-current-user/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__get-current-user", implemented, .{
        .summary = "Parity implementation for tutorial/security/get-current-user/",
        .tags = &.{ "parity", "tutorial" },
    });
}
