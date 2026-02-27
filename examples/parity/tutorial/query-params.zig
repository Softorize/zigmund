const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/query-params/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/query-params/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-params", placeholder, .{
        .summary = "Parity stub for tutorial/query-params/",
        .tags = &.{"parity", "tutorial"},
    });
}
