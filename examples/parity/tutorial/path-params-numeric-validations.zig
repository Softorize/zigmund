const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/path-params-numeric-validations/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/path-params-numeric-validations/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-params-numeric-validations", placeholder, .{
        .summary = "Parity stub for tutorial/path-params-numeric-validations/",
        .tags = &.{"parity", "tutorial"},
    });
}
