const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/static-files/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/static-files/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/static-files", placeholder, .{
        .summary = "Parity stub for tutorial/static-files/",
        .tags = &.{"parity", "tutorial"},
    });
}
