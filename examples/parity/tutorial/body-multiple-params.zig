const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/body-multiple-params/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/body-multiple-params/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/body-multiple-params", placeholder, .{
        .summary = "Parity stub for tutorial/body-multiple-params/",
        .tags = &.{"parity", "tutorial"},
    });
}
