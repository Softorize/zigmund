const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: advanced/additional-status-codes/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "advanced/additional-status-codes/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/additional-status-codes", placeholder, .{
        .summary = "Parity stub for advanced/additional-status-codes/",
        .tags = &.{"parity", "advanced"},
    });
}
