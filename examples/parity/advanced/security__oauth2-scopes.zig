const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/security/oauth2-scopes/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/security__oauth2-scopes", implemented, .{
        .summary = "Parity implementation for advanced/security/oauth2-scopes/",
        .tags = &.{ "parity", "advanced" },
    });
}
