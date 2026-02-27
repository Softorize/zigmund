const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/request-files/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/request-files/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/request-files", placeholder, .{
        .summary = "Parity stub for tutorial/request-files/",
        .tags = &.{"parity", "tutorial"},
    });
}
