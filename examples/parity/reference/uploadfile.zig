const std = @import("std");
const zigmund = @import("zigmund");

// ZIGMUND_PARITY_STUB
// FastAPI source page: reference/uploadfile/

fn placeholder(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "stub",
        .page = "reference/uploadfile/",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/uploadfile", placeholder, .{
        .summary = "Parity stub for reference/uploadfile/",
        .tags = &.{"parity", "reference"},
    });
}
