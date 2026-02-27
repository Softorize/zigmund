const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/staticfiles/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/staticfiles/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/staticfiles", placeholder, .{
        .summary = "Parity stub for reference/staticfiles/",
        .tags = &.{"parity", "reference"},
    });
}
