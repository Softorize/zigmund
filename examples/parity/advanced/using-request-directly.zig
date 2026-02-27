const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/using-request-directly/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/using-request-directly/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/using-request-directly", placeholder, .{
        .summary = "Parity stub for advanced/using-request-directly/",
        .tags = &.{"parity", "advanced"},
    });
}
