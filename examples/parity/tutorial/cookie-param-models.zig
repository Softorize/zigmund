const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/cookie-param-models/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/cookie-param-models/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/cookie-param-models", placeholder, .{
        .summary = "Parity stub for tutorial/cookie-param-models/",
        .tags = &.{"parity", "tutorial"},
    });
}
