const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/behind-a-proxy/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/behind-a-proxy/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/behind-a-proxy", placeholder, .{
        .summary = "Parity stub for advanced/behind-a-proxy/",
        .tags = &.{"parity", "advanced"},
    });
}
