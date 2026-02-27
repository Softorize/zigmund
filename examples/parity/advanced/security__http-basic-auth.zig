const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/security/http-basic-auth/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/security__http-basic-auth", implemented, .{
        .summary = "Parity implementation for advanced/security/http-basic-auth/",
        .tags = &.{ "parity", "advanced" },
    });
}
