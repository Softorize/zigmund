const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/index", placeholder, .{
        .summary = "Parity stub for reference/",
        .tags = &.{"parity", "reference"},
    });
}
