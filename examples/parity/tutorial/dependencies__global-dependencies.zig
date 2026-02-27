const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/dependencies/global-dependencies/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/dependencies/global-dependencies/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__global-dependencies", placeholder, .{
        .summary = "Parity stub for tutorial/dependencies/global-dependencies/",
        .tags = &.{"parity", "tutorial"},
    });
}
