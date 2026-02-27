const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/response-status-code/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/response-status-code/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/response-status-code", placeholder, .{
        .summary = "Parity stub for tutorial/response-status-code/",
        .tags = &.{"parity", "tutorial"},
    });
}
