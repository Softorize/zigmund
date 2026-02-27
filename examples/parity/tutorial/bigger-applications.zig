const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/bigger-applications/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/bigger-applications/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/bigger-applications", placeholder, .{
        .summary = "Parity stub for tutorial/bigger-applications/",
        .tags = &.{"parity", "tutorial"},
    });
}
