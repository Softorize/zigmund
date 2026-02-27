const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/encoders/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/encoders/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/encoders", placeholder, .{
        .summary = "Parity stub for reference/encoders/",
        .tags = &.{"parity", "reference"},
    });
}
