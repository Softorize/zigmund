const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/testing-events/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/testing-events/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/testing-events", placeholder, .{
        .summary = "Parity stub for advanced/testing-events/",
        .tags = &.{"parity", "advanced"},
    });
}
