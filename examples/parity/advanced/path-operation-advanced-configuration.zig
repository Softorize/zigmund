const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/path-operation-advanced-configuration/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/path-operation-advanced-configuration/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/path-operation-advanced-configuration", placeholder, .{
        .summary = "Parity stub for advanced/path-operation-advanced-configuration/",
        .tags = &.{"parity", "advanced"},
    });
}
