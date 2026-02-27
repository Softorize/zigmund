const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/security/http-basic-auth/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/security/http-basic-auth/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/security__http-basic-auth", placeholder, .{
        .summary = "Parity stub for advanced/security/http-basic-auth/",
        .tags = &.{"parity", "advanced"},
    });
}
