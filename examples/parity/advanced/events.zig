const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/events/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/events/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/events", placeholder, .{
        .summary = "Parity stub for advanced/events/",
        .tags = &.{"parity", "advanced"},
    });
}
