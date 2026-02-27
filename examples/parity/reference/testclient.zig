const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/testclient/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/testclient/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/testclient", placeholder, .{
        .summary = "Parity stub for reference/testclient/",
        .tags = &.{"parity", "reference"},
    });
}
