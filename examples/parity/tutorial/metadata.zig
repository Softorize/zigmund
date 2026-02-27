const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/metadata/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/metadata/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/metadata", placeholder, .{
        .summary = "Parity stub for tutorial/metadata/",
        .tags = &.{"parity", "tutorial"},
    });
}
