const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/additional-responses/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/additional-responses/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/additional-responses", placeholder, .{
        .summary = "Parity stub for advanced/additional-responses/",
        .tags = &.{"parity", "advanced"},
    });
}
