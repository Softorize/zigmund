const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/header-param-models/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/header-param-models/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/header-param-models", placeholder, .{
        .summary = "Parity stub for tutorial/header-param-models/",
        .tags = &.{"parity", "tutorial"},
    });
}
