const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/testing-dependencies/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/testing-dependencies/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/testing-dependencies", placeholder, .{
        .summary = "Parity stub for advanced/testing-dependencies/",
        .tags = &.{"parity", "advanced"},
    });
}
