const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/wsgi/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/wsgi/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/wsgi", placeholder, .{
        .summary = "Parity stub for advanced/wsgi/",
        .tags = &.{"parity", "advanced"},
    });
}
