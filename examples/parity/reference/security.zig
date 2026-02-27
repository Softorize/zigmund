const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/security/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/security/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/security", placeholder, .{
        .summary = "Parity stub for reference/security/",
        .tags = &.{"parity", "reference"},
    });
}
