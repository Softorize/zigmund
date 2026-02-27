const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/dependencies/sub-dependencies/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/dependencies/sub-dependencies/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__sub-dependencies", placeholder, .{
        .summary = "Parity stub for tutorial/dependencies/sub-dependencies/",
        .tags = &.{"parity", "tutorial"},
    });
}
