const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/openapi/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/openapi/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/openapi", placeholder, .{
        .summary = "Parity stub for reference/openapi/",
        .tags = &.{"parity", "reference"},
    });
}
