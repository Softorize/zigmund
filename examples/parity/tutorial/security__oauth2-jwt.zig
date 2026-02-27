const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/security/oauth2-jwt/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/security/oauth2-jwt/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/security__oauth2-jwt", placeholder, .{
        .summary = "Parity stub for tutorial/security/oauth2-jwt/",
        .tags = &.{"parity", "tutorial"},
    });
}
