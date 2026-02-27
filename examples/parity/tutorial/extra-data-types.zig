const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/extra-data-types/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/extra-data-types/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/extra-data-types", placeholder, .{
        .summary = "Parity stub for tutorial/extra-data-types/",
        .tags = &.{"parity", "tutorial"},
    });
}
