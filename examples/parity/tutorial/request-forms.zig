const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/request-forms/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/request-forms/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/request-forms", placeholder, .{
        .summary = "Parity stub for tutorial/request-forms/",
        .tags = &.{"parity", "tutorial"},
    });
}
