const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/body-fields/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/body-fields/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/body-fields", placeholder, .{
        .summary = "Parity stub for tutorial/body-fields/",
        .tags = &.{"parity", "tutorial"},
    });
}
