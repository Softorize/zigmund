const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/schema-extra-example/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/schema-extra-example/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/schema-extra-example", placeholder, .{
        .summary = "Parity stub for tutorial/schema-extra-example/",
        .tags = &.{"parity", "tutorial"},
    });
}
