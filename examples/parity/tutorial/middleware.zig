const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/middleware/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/middleware/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/middleware", placeholder, .{
        .summary = "Parity stub for tutorial/middleware/",
        .tags = &.{"parity", "tutorial"},
    });
}
