const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/openapi/models/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/openapi/models/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/openapi__models", placeholder, .{
        .summary = "Parity stub for reference/openapi/models/",
        .tags = &.{"parity", "reference"},
    });
}
