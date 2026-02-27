const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/handling-errors/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/handling-errors/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/handling-errors", placeholder, .{
        .summary = "Parity stub for tutorial/handling-errors/",
        .tags = &.{"parity", "tutorial"},
    });
}
