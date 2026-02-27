const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/middleware/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/middleware/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/middleware", placeholder, .{
        .summary = "Parity stub for advanced/middleware/",
        .tags = &.{"parity", "advanced"},
    });
}
