const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/dataclasses/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/dataclasses/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/dataclasses", placeholder, .{
        .summary = "Parity stub for advanced/dataclasses/",
        .tags = &.{"parity", "advanced"},
    });
}
