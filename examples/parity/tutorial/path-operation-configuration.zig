const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/path-operation-configuration/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/path-operation-configuration/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-operation-configuration", placeholder, .{
        .summary = "Parity stub for tutorial/path-operation-configuration/",
        .tags = &.{"parity", "tutorial"},
    });
}
