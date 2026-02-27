const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/request/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/request/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/request", placeholder, .{
        .summary = "Parity stub for reference/request/",
        .tags = &.{"parity", "reference"},
    });
}
