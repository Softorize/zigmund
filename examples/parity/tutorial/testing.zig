const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/testing/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/testing/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/testing", placeholder, .{
        .summary = "Parity stub for tutorial/testing/",
        .tags = &.{"parity", "tutorial"},
    });
}
