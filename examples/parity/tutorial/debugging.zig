const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/debugging/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/debugging/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/debugging", placeholder, .{
        .summary = "Parity stub for tutorial/debugging/",
        .tags = &.{"parity", "tutorial"},
    });
}
