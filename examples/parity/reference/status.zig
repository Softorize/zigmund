const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/status/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/status/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/status", placeholder, .{
        .summary = "Parity stub for reference/status/",
        .tags = &.{"parity", "reference"},
    });
}
