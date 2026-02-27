const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/request-form-models/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/request-form-models/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/request-form-models", placeholder, .{
        .summary = "Parity stub for tutorial/request-form-models/",
        .tags = &.{"parity", "tutorial"},
    });
}
