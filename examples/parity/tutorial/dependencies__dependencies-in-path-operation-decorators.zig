const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/dependencies/dependencies-in-path-operation-decorators/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/dependencies/dependencies-in-path-operation-decorators/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/dependencies__dependencies-in-path-operation-decorators", placeholder, .{
        .summary = "Parity stub for tutorial/dependencies/dependencies-in-path-operation-decorators/",
        .tags = &.{"parity", "tutorial"},
    });
}
