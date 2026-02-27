const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/dependencies/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/dependencies/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/dependencies", placeholder, .{
        .summary = "Parity stub for reference/dependencies/",
        .tags = &.{"parity", "reference"},
    });
}
