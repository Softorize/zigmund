const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: tutorial/sql-databases/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "tutorial/sql-databases/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/sql-databases", placeholder, .{
        .summary = "Parity stub for tutorial/sql-databases/",
        .tags = &.{"parity", "tutorial"},
    });
}
