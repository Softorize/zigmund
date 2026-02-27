const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/advanced-python-types/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/advanced-python-types/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/advanced-python-types", placeholder, .{
        .summary = "Parity stub for advanced/advanced-python-types/",
        .tags = &.{"parity", "advanced"},
    });
}
