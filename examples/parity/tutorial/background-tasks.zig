const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/background-tasks/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/background-tasks/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/background-tasks", placeholder, .{
        .summary = "Parity stub for tutorial/background-tasks/",
        .tags = &.{"parity", "tutorial"},
    });
}
