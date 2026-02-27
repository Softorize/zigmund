const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/middleware/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/middleware/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/middleware", placeholder, .{
        .summary = "Parity stub for reference/middleware/",
        .tags = &.{"parity", "reference"},
    });
}
