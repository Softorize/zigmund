const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/response-headers/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/response-headers/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/response-headers", placeholder, .{
        .summary = "Parity stub for advanced/response-headers/",
        .tags = &.{"parity", "advanced"},
    });
}
