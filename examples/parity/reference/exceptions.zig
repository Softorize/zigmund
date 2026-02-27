const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/exceptions/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/exceptions/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/exceptions", placeholder, .{
        .summary = "Parity stub for reference/exceptions/",
        .tags = &.{"parity", "reference"},
    });
}
