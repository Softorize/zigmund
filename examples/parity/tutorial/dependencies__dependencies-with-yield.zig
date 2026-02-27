const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/dependencies/dependencies-with-yield/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/dependencies/dependencies-with-yield/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__dependencies-with-yield", placeholder, .{
        .summary = "Parity stub for tutorial/dependencies/dependencies-with-yield/",
        .tags = &.{"parity", "tutorial"},
    });
}
