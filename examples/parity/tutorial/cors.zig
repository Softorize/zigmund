const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/cors/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/cors/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/cors", placeholder, .{
        .summary = "Parity stub for tutorial/cors/",
        .tags = &.{"parity", "tutorial"},
    });
}
