const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/response-directly/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/response-directly/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-directly", placeholder, .{
        .summary = "Parity stub for advanced/response-directly/",
        .tags = &.{"parity", "advanced"},
    });
}
