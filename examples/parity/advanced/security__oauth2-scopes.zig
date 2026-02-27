const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/security/oauth2-scopes/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/security/oauth2-scopes/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/security__oauth2-scopes", placeholder, .{
        .summary = "Parity stub for advanced/security/oauth2-scopes/",
        .tags = &.{"parity", "advanced"},
    });
}
