const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/security/oauth2-jwt/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__oauth2-jwt", implemented, .{
        .summary = "Parity implementation for tutorial/security/oauth2-jwt/",
        .tags = &.{ "parity", "tutorial" },
    });
}
